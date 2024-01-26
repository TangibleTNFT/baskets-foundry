// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

// tangible imports
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IRWAPriceNotificationDispatcher } from "@tangible/interfaces/IRWAPriceNotificationDispatcher.sol";
import { INotificationWhitelister } from "@tangible/interfaces/INotificationWhitelister.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";

// local imports
import { Basket } from "./Basket.sol";
import { IBasket } from "./interfaces/IBasket.sol";
import { BasketBeaconProxy } from "./proxy/beacon/BasketBeaconProxy.sol";
import { IGetNotificationDispatcher } from "./interfaces/IGetNotificationDispatcher.sol";

/**
 * @title BasketManager
 * @author Chase Brown
 * @notice This contract manages all Basket contracts.
 */
contract BasketManager is UUPSUpgradeable, FactoryModifiers {

    // ---------------
    // State Variables
    // ---------------

    /**
     * @notice Data structure for storing basket information
     * @param hashedFeatures stores the unique feature combination hash for each basket.
     * @param basketName stores the name of the basket basket.
     * @param basketSymbol stores the symbol of the basket.
     */
    struct BasketInfo {
        bytes32 hashedFeatures;
        string basketName;
        string basketSymbol;
    }

    /// @notice Mapping that stores a baskets's information, given it's address as a key.
    mapping(address => BasketInfo) public getBasketInfo;

    /// @notice This mapping provides a low-gas method to checking the availability of a name for a new basket.
    mapping(string => bool) public nameHashTaken;

    /// @notice This mapping provides a low-gas method to checking the availability of a symbol for a new basket.
    mapping(string => bool) public symbolHashTaken;

    /// @notice Returns the address of the basket, given it's unique hash.
    /// @dev Mainly implemented for the front end.
    mapping(bytes32 => address) public fetchBasketByHash;

    /// @notice Limit of amount of features allowed per basket.
    uint256 public featureLimit;

    /// @notice This variable caches the most recent hash created for a new basket.
    /// @dev Created primarily in response to stack-too-deep errors when calling `deployBasket`.
    bytes32 internal _hashCache;

    /// @notice Array of all baskets deployed.
    address[] public baskets;

    /// @notice UpgradeableBeacon contract instance. Deployed by this contract upon initialization.
    UpgradeableBeacon public beacon;

    /// @notice Contract address of basketsVrfConsumer contract.
    address public basketsVrfConsumer;

    /// @notice This stores the contract address of the revenue distributor contract.
    address public revenueDistributor;


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when a new basket instance is created // beaconProxy deployed.
     * @param creator Address of deployer.
     * @param basket Address of basket deployed.
     */
    event BasketCreated(address indexed creator, address indexed basket);


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice Initializes BasketManager contract.
     * @param _initBasketImplementation Contract address of Basket implementation contract.
     * @param _factory Contract address of Factory contract.
     */
    function initialize(address _initBasketImplementation, address _factory) external initializer {
        require(_initBasketImplementation != address(0), "Cannot init with address(0)");
        require(_factory != address(0), "Cannot init with address(0)");

        __FactoryModifiers_init(_factory);
        beacon = new UpgradeableBeacon(
            _initBasketImplementation,
            address(this)
        );

        featureLimit = 10;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method deploys a new Basket contract.
     * @dev This func will only deploy a beacon proxy with the implementation being the basket contract.
     * @param _name Name of new basket.
     * @param _symbol Symbol of new basket.
     * @param _tnftType Tnft category supported by basket.
     * @param _rentToken ERC-20 token being used for rent. USDC by default.
     * @param _location ISO country code for supported location of basket.
     * @param _features Array of uint feature identifiers (subcategories) supported by basket.
     * @param _tangibleNFTDeposit Array of tnft addresses of tokens being deposited into basket initially.
     * @param _tokenIdDeposit Array of tokenIds being deposited into basket initally. Note: Corresponds with _tangibleNFTDeposit.
     */
    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType,
        address _rentToken,
        uint16 _location,
        uint256[] memory _features,
        address[] memory _tangibleNFTDeposit,
        uint256[] memory _tokenIdDeposit
    ) external returns (IBasket, uint256[] memory basketShares) {
        // verify _tanfibleNFTDeposit array and _tokenIdDeposit array are the same size.
        require(_tangibleNFTDeposit.length == _tokenIdDeposit.length, "Differing lengths");

        // verify deployer is depositing an initial token into basket.
        require(_tangibleNFTDeposit.length !=0, "Must be an initial deposit");

        // verify _features does not have more features that what is allowed.
        require(featureLimit >= _features.length, "Too many features");

        // verify _tnftType is a supported type in the Metadata contract.
        (bool added,,) = ITNFTMetadata(IFactory(factory()).tnftMetadata()).tnftTypes(_tnftType);
        require(added, "Invalid tnftType");

        // verify _name is unique and available
        require(!nameHashTaken[_name], "Name not available");

        // verify _symbol is unique and available
        require(!symbolHashTaken[_symbol], "Symbol not available");

        // if features array contains more than 1 element, verify no duplicates and is sorted
        if (_features.length > 1) {
            require(_verifySortedNoDuplicates(_features), "features not sorted or duplicates");
        }

        // create unique hash for new basket
        _hashCache = createHash(_tnftType, _location, _features);

        // check basket availability
        require(fetchBasketByHash[_hashCache] == address(0), "Basket already exists");

        // check features are valid.
        for (uint256 i; i < _features.length;) {
            require(ITNFTMetadata(IFactory(factory()).tnftMetadata()).featureInType(_tnftType, _features[i]), "Feature not supported in type");
            unchecked {
                ++i;
            }
        }

        // create new basket beacon proxy
        BasketBeaconProxy newBasketBeacon = new BasketBeaconProxy(
            address(beacon),
            abi.encodeWithSelector(Basket.initialize.selector,
                _name,
                _symbol,
                factory(),
                _tnftType,
                _rentToken,
                _features,
                _location,
                msg.sender
            )
        );

        // store hash and new newBasketBeacon
        baskets.push(address(newBasketBeacon));

        getBasketInfo[address(newBasketBeacon)] = BasketInfo({
            hashedFeatures: _hashCache,
            basketName: _name,
            basketSymbol: _symbol
        });

        nameHashTaken[_name] = true;
        symbolHashTaken[_symbol] = true;

        fetchBasketByHash[_hashCache] = address(newBasketBeacon);

        // transfer initial TNFT from newBasketBeacon owner to this contract and approve transfer of TNFT to new basket
        for (uint256 i; i < _tokenIdDeposit.length;) {
            IPriceOracle oracle = ITangiblePriceManager(address(IFactory(factory()).priceManager())).oracleForCategory(ITangibleNFT(_tangibleNFTDeposit[i]));
            IRWAPriceNotificationDispatcher notificationDispatcher = IGetNotificationDispatcher(address(oracle)).notificationDispatcher();

            if (!INotificationWhitelister(address(notificationDispatcher)).whitelistedReceiver(address(newBasketBeacon))) {
                INotificationWhitelister(address(notificationDispatcher)).whitelistAddressAndReceiver(address(newBasketBeacon));
            }

            IERC721(_tangibleNFTDeposit[i]).safeTransferFrom(msg.sender, address(this), _tokenIdDeposit[i]);
            IERC721(_tangibleNFTDeposit[i]).approve(address(newBasketBeacon), _tokenIdDeposit[i]);
            unchecked {
                ++i;
            }
        }

        // call batchDepositTNFT
        basketShares = IBasket(address(newBasketBeacon)).batchDepositTNFT(_tangibleNFTDeposit, _tokenIdDeposit);

        emit BasketCreated(msg.sender, address(newBasketBeacon));
        return (IBasket(address(newBasketBeacon)), basketShares);
    }

    /**
     * @notice Withdraws any ERC20 token balance of this contract into the multisig wallet.
     * @param _contract Address of an ERC20 compliant token.
     */
    function withdrawERC20(address _contract) external onlyFactoryOwner {
        require(_contract != address(0), "Address cannot be zero address");

        uint256 balance = IERC20(_contract).balanceOf(address(this));
        require(balance > 0, "Insufficient token balance");

        require(IERC20(_contract).transfer(msg.sender, balance), "Transfer failed on ERC20 contract");
    }

    /**
     * @notice This function allows the factory owner to update the Basket implementation.
     * @param _newBasketImp Address of new Basket contract implementation.
     */
    function updateBasketImplementation(address _newBasketImp) external onlyFactoryOwner {
        beacon.upgradeTo(_newBasketImp);
    }

    /**
     * @notice This method allows the factory owner to update the `basketsVrfConsumer` contract address.
     * @param _basketsVrfConsumer New contract address.
     */
    function setBasketsVrfConsumer(address _basketsVrfConsumer) external onlyFactoryOwner {
        require(_basketsVrfConsumer != address(0), "_basketsVrfConsumer == address(0)");
        basketsVrfConsumer = _basketsVrfConsumer;
    }

    /**
     * @notice This method allows the factory owner to update the `revenueDistributor` contract address.
     * @param _revenueDistributor New contract address.
     */
    function setRevenueDistributor(address _revenueDistributor) external onlyFactoryOwner {
        require(_revenueDistributor != address(0), "_revenueDistributor == address(0)");
        revenueDistributor = _revenueDistributor;
    }

    /**
     * @notice This method allows the factory owner to update the limit of features a basket can support.
     * @param _limit New feature limit.
     */
    function setFeatureLimit(uint256 _limit) external onlyFactoryOwner {
        require(_limit != featureLimit, "Already set");
        featureLimit = _limit;
    }

    /**
     * @notice View method for fetching baskets array.
     * @return baskets array.
     */
    function getBasketsArray() external view returns (address[] memory) {
        return baskets;
    }

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice This method is used for querying whether a provided address is one of a basket.
     * @param _basket Address of basket.
     * @return isBasket -> If true, `_basket` is a basket.
     */
    function isBasket(address _basket) public view returns (bool isBasket) {
        getBasketInfo[_basket].hashedFeatures != bytes32(0) ? isBasket = true : isBasket = false;
    }

    /**
     * @notice This method is used to create a unique hash given a category and list of sub categories.
     * @param _tnftType Category identifier.
     * @param _location ISO Code for country.
     * @param _features List of subcategories.
     */
    function createHash(uint256 _tnftType, uint16 _location, uint256[] memory _features) public pure returns (bytes32 hashedFeatures) {
        hashedFeatures = keccak256(abi.encodePacked(_tnftType, _location, _features));
    }


    // ----------------
    // Internal Methods
    // ----------------

    function _verifySortedNoDuplicates(uint256[] memory _features) internal view returns (bool isSorted) {
        uint256 length = _features.length - 1;
        for (uint256 i; i < length;) {

            // if greater-than => not sorted
            // if equal-to => duplicates
            if (_features[i] >= _features[i+1]) return false;

            unchecked {
                ++i;
            }
        }
        return true;
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the factory owner to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyFactoryOwner {}
}