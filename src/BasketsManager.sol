// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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
import { ArrayUtils } from "./libraries/ArrayUtils.sol";
import { UpgradeableBeacon } from "./proxy/UpgradeableBeacon.sol";
import { BasketBeaconProxy } from "./proxy/BasketBeaconProxy.sol";
import { IGetNotificationDispatcher } from "./interfaces/IGetNotificationDispatcher.sol";


/**
 * @title BasketManager
 * @author Chase Brown
 * @notice This contract manages all Basket contracts.
 */
contract BasketManager is Initializable, FactoryModifiers {
    using ArrayUtils for uint256[];

    // ~ State Variables ~

    /// @notice Mapping that stores the unique `featureHash` for each basket.
    mapping(address => bytes32) public hashedFeaturesForBasket;

    /// @notice Mapping that stores whether a specified address is a basket.
    mapping(address => bool) public isBasket;

    /// @notice Mapping that stores each name (as a hash) for each basket.
    mapping(address => bytes32) public basketNames;

    /// @notice Mapping that stores each symbol (as a hash) for each basket.
    mapping(address => bytes32) public basketSymbols;

    /// @notice UpgradeableBeacon contract instance. Deployed by this contract upon initialization.
    UpgradeableBeacon public beacon;

    /// @notice Array of all baskets deployed.
    address[] public baskets;

    /// @notice Limit of amount of features allowed per basket.
    uint256 public featureLimit;

    /// @notice Used to save slots for potential extra state variables later on.
    uint256[20] private __gap;


    // ~ Events ~

    /**
     * @notice This event is emitted when a new basket instance is created // beaconProxy deployed.
     * @param creator Address of deployer.
     * @param basket Address of basket deployed.
     */
    event BasketCreated(address creator, address basket);


    // ~ Modifiers ~

    /// @notice Modifier verifying msg.sender is a valid Basket contract.
    modifier onlyBasket() {
        require(isBasket[msg.sender], "Caller is not valid basket");
        _;
    }


    // ~ Constructor ~

    constructor() {
        _disableInitializers();
    }


    // ~ Initializer ~

    /**
     * @notice Initializes BasketManager contract.
     * @param _initBasketImplementation Contract address of Basket implementation contract.
     * @param _factory Contract address of Factory contract.
     */
    function initialize(address _initBasketImplementation, address _factory) external initializer {
        __FactoryModifiers_init(_factory);
        beacon = new UpgradeableBeacon(
            _initBasketImplementation,
            address(this) // TODO: Test to see implications of new owner
        );

        featureLimit = 10;
    }


    // ~ External Functions ~

    /**
     * @notice This method deploys a new Basket contract.
     * @dev This func will only deploy a beacon proxy with the implementation being the basket contract.
     * @param _name Name of new basket.
     * @param _symbol Symbol of new basket.
     * @param _tnftType Tnft category supported by basket.
     * @param _rentToken ERC-20 token being used for rent. USDC by default.
     * @param _features Array of uint feature identifiers (subcategories) supported by basket.
     * @param _tangibleNFTDeposit Array of tnft addresses of tokens being deposited into basket initially.
     * @param _tokenIdDeposit Array of tokenIds being deposited into basket initally. Note: Corresponds with _tangibleNFTDeposit.
     */
    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType,
        address _rentToken,
        uint256[] memory _features,
        address[] memory _tangibleNFTDeposit,
        uint256[] memory _tokenIdDeposit
    ) external returns (IBasket, uint256[] memory basketShares) {
        // verify _tanfibleNFTDeposit array and _tokenIdDeposit array are the same size.
        require(_tangibleNFTDeposit.length == _tokenIdDeposit.length, "Differing lengths");

        // verify _features does not have more features that what is allowed.
        require(featureLimit >= _features.length, "Too many features");

        // verify _tnftType is a supported type in the Metadata contract.
        address metadata = IFactory(factory()).tnftMetadata();
        (bool added,,) = ITNFTMetadata(metadata).tnftTypes(_tnftType);
        require(added, "Invalid tnftType");

        // verify _name is unique and available
        require(checkBasketNameAvailability(keccak256(abi.encodePacked(_name))), "Name not available");

        // verify _symbol is unique and available
        require(checkBasketSymbolAvailability(keccak256(abi.encodePacked(_symbol))), "Symbol not available");

        // create unique hash
        bytes32 hashedFeatures = createHash(_tnftType, _features);

        // might not be necessary -> hash is checked when Basket is initialized
        require(checkBasketAvailability(hashedFeatures), "Basket already exists");

        // check features are valid.
        for (uint256 i; i < _features.length;) {
            require(ITNFTMetadata(metadata).featureInType(_tnftType, _features[i]), "Feature not supported in type");
            unchecked {
                ++i;
            }
        }

        // create new basket beacon proxy
        BasketBeaconProxy newBasketBeacon = new BasketBeaconProxy(
            address(beacon),
            abi.encodeWithSelector(Basket.initialize.selector,  // TODO: Verify all this data is indeed being stored in proxy
                _name,
                _symbol,
                factory(),
                _tnftType,
                _rentToken,
                _features,
                msg.sender
            )
        );

        // store hash and new newBasketBeacon
        baskets.push(address(newBasketBeacon));

        hashedFeaturesForBasket[address(newBasketBeacon)] = hashedFeatures;
        isBasket[address(newBasketBeacon)] = true;

        basketNames[address(newBasketBeacon)] = keccak256(abi.encodePacked(_name));
        basketSymbols[address(newBasketBeacon)] = keccak256(abi.encodePacked(_symbol));

        // fetch priceManager to whitelist basket for notifications on RWApriceNotificationDispatcher
        ITangiblePriceManager priceManager = IFactory(factory()).priceManager();

        // transfer initial TNFT from newBasketBeacon owner to this contract and approve transfer of TNFT to new basket
        for (uint256 i; i < _tokenIdDeposit.length;) {
            IPriceOracle oracle = ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFTDeposit[i]));
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


    // ~ Public Functions ~

    /**
     * @notice This method checks whether a basket with featuresHash can be created or is taken.
     * @dev A featuresHash is a unique hash assigned each basket contract and is created based on the unique
     *      combination of features that basket supports. No 2 baskets that support same combo can co-exist.
     * @param _featuresHash unique bytes32 hash created from combination of features
     * @return If true, features combo is available to be created. If false, already exists.
     */
    function checkBasketAvailability(bytes32 _featuresHash) public view returns (bool) {
        for (uint256 i; i < baskets.length;) {
            if (hashedFeaturesForBasket[baskets[i]] == _featuresHash) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /**
     * @notice This method checks whether a basket with a given name is taken.
     * @dev No 2 baskets that have the same name can co-exist.
     * @param _nameHash unique bytes32 hash created from string name.
     * @return If true, name is available to be created. If false, already exists.
     */
    function checkBasketNameAvailability(bytes32 _nameHash) public view returns (bool) { // TODO: Taken off chain?
        for (uint256 i; i < baskets.length;) {
            if (basketNames[baskets[i]] == _nameHash) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /**
     * @notice This method checks whether a basket with a given symbol is taken.
     * @dev No 2 baskets that have the same symbol can co-exist.
     * @param _symbolHash unique bytes32 hash created from string symbol.
     * @return If true, symbol is available to be created. If false, already exists.
     */
    function checkBasketSymbolAvailability(bytes32 _symbolHash) public view returns (bool) {
        for (uint256 i; i < baskets.length;) {
            if (basketSymbols[baskets[i]] == _symbolHash) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /**
     * @notice This method is used to create a unique hash given a category and list of sub categories.
     * @param _tnftType Category identifier.
     * @param _features List of subcategories.
     */
    function createHash(uint256 _tnftType, uint256[] memory _features) public pure returns (bytes32 hashedFeatures) {
        hashedFeatures = keccak256(abi.encodePacked(_tnftType, _features.sort()));
    }

}
