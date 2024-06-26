// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

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
import { ICurrencyCalculator } from "./interfaces/ICurrencyCalculator.sol";
import { IGetNotificationDispatcher } from "./interfaces/IGetNotificationDispatcher.sol";

/**
 * @title BasketManager
 * @author Chase Brown
 * @notice This contract manages all Basket contracts.
 */
contract BasketManager is UUPSUpgradeable, ReentrancyGuardUpgradeable, FactoryModifiers {
    using SafeERC20 for IERC20;

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
        bool isBasket;
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

    /// @notice This stores the ERC20 contract address of the primary rent token for baskets.
    address public primaryRentToken;

    /// @notice Rebase controller address stored here.
    address public rebaseController;

    /// @notice CurrencyCalculator contract address.
    ICurrencyCalculator public currencyCalculator;

    /// @notice Is used to cache the initialize data for new baskets.
    bytes internal initData;

    /// @notice If the `primaryRentToken` is a rebase token, this should be true.
    bool public rentIsRebaseToken;


    // ------
    // Events
    // ------

    /// @notice Emitted when a new basket instance is created.
    event BasketCreated(address indexed creator, address indexed basket);
    /// @notice Emitted when the primaryRentToken variable is updated.
    event PrimaryRentTokenUpdated(address indexed newPrimaryRentToken);
    /// @notice Emitted when the rebaseController is updated.
    event RebaseControllerUpdated(address indexed newController);
    /// @notice Emitted when the basket implementation address is updated on the upgradeable beacon.
    event BasketImplementationUpdated(address indexed newBasketImplementation);
    /// @notice Emitted when the basketsVrfConsumer address is updated.
    event BasketsVrfConsumerUpdated(address indexed newBasketsVrfConsumer);
    /// @notice Emitted when the RevenueDistributor address is updated.
    event RevenueDistributorUpdated(address indexed newRevenueDistributor);
    /// @notice Emitted when the CurrencyCalculator address is updated.
    event CurrencyCalculatorUpdated(address indexed newCurrencyCalculator);
    /// @notice Emitted when the featureLimit variable is updated.
    event FeatureLimitUpdated(uint256 indexed newLimit);


    // ------
    // Errors
    // ------

    /// @dev Emitted when an input address is a zero address.
    error ZeroAddress();
    /// @dev Emitted when there is a withdraw of an asset amount that exceeds this contract's balance.
    error InsufficientBalance();
    /// @dev Emitted when the _tangibleNFTDeposit and _tokenIdDeposit are not acceptable lengths.
    error InvalidArrayEntry();
    /// @dev Emitted when the features array size for creating a new basket exceeds the limit.
    error FeatureLimitExceeded();
    /// @dev Emitted when a tnft type is input into a new basket, but is not a valid type.
    error InvalidTnftType(uint256 tnftType);
    /// @dev Emitted when a new basket is being created with a name that is already taken.
    error NameNotAvailable(string name);
    /// @dev Emitted when a new basket is being created with a symbol that is already taken.
    error SymbolNotAvailable(string symbol);
    /// @dev Emitted when a new basket is being created with a _features array that is not sorted.
    error FeaturesNotSorted();
    /// @dev Emitted when a new basket is being created with features that are not unique.
    error BasketAlreadyExists();
    /// @dev Emitted when the features of a new basket are not supported by it's tnft type.
    error FeatureNotSupportedInType(uint256 tnftType, uint256 feature);


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
     * @param _rentToken Primary rent token address.
     * @param _currencyCalculator CurrencyCalculator address.
     */
    function initialize(
        address _initBasketImplementation,
        address _factory,
        address _rentToken,
        bool _rentIsRebaseToken,
        address _currencyCalculator
    ) external initializer {
        if (_initBasketImplementation == address(0) ||
            _factory == address(0) ||
            _rentToken == address(0) ||
            _currencyCalculator == address(0)) revert ZeroAddress();

        __FactoryModifiers_init(_factory);
        __ReentrancyGuard_init();

        beacon = new UpgradeableBeacon(
            _initBasketImplementation,
            address(this)
        );

        currencyCalculator = ICurrencyCalculator(_currencyCalculator);
        primaryRentToken = _rentToken;
        rentIsRebaseToken = _rentIsRebaseToken;
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
     * @param _location ISO country code for supported location of basket.
     * @param _features Array of uint feature identifiers (subcategories) supported by basket.
     * @dev `_features` MUST be sorted upon function call. 
     * @param _tangibleNFTDeposit Array of tnft addresses of tokens being deposited into basket initially.
     * @param _tokenIdDeposit Array of tokenIds being deposited into basket initally. Note: Corresponds with _tangibleNFTDeposit.
     */
    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType,
        uint16 _location,
        uint256[] memory _features,
        address[] memory _tangibleNFTDeposit,
        uint256[] memory _tokenIdDeposit
    ) external nonReentrant returns (IBasket, uint256[] memory basketShares) {
        // verify _tanfibleNFTDeposit array and _tokenIdDeposit array are the same size & not 0.
        if (_tangibleNFTDeposit.length != _tokenIdDeposit.length || _tangibleNFTDeposit.length == 0) revert InvalidArrayEntry();

        // verify _features does not have more features that what is allowed.
        if (_features.length > featureLimit) revert FeatureLimitExceeded();

        // verify _tnftType is a supported type in the Metadata contract.
        (bool added,,) = ITNFTMetadata(IFactory(factory()).tnftMetadata()).tnftTypes(_tnftType);
        if (!added) revert InvalidTnftType(_tnftType);

        // verify _name & _symbol are unique and available
        if (nameHashTaken[_name]) revert NameNotAvailable(_name);
        if (symbolHashTaken[_symbol]) revert SymbolNotAvailable(_symbol);

        // if features array contains more than 1 element, verify no duplicates and is sorted
        if (_features.length > 1) {
            if (!_verifySortedNoDuplicates(_features)) revert FeaturesNotSorted();
        }

        // create unique hash for new basket
        _hashCache = createHash(_tnftType, _location, _features);

        // check basket availability
        if (fetchBasketByHash[_hashCache] != address(0)) revert BasketAlreadyExists();

        // check features are valid.
        for (uint256 i; i < _features.length; ++i) {
            if (!ITNFTMetadata(IFactory(factory()).tnftMetadata()).featureInType(_tnftType, _features[i]))
                revert FeatureNotSupportedInType(_tnftType, _features[i]);
        }

        initData = abi.encodeWithSelector(
            Basket.initialize.selector,
            _name,
            _symbol,
            factory(),
            _tnftType,
            primaryRentToken,
            rentIsRebaseToken,
            _features,
            _location,
            msg.sender
        );

        // create new basket beacon proxy
        BeaconProxy newBasketBeacon = new BeaconProxy(
            address(beacon),
            initData
        );

        // store hash and new newBasketBeacon
        baskets.push(address(newBasketBeacon));

        getBasketInfo[address(newBasketBeacon)] = BasketInfo({
            hashedFeatures: _hashCache,
            basketName: _name,
            basketSymbol: _symbol,
            isBasket: true
        });

        nameHashTaken[_name] = true;
        symbolHashTaken[_symbol] = true;

        fetchBasketByHash[_hashCache] = address(newBasketBeacon);

        // transfer initial TNFT from newBasketBeacon owner to this contract and approve transfer of TNFT to new basket
        for (uint256 i; i < _tokenIdDeposit.length; ++i) {
            IPriceOracle oracle = ITangiblePriceManager(address(IFactory(factory()).priceManager())).oracleForCategory(ITangibleNFT(_tangibleNFTDeposit[i]));
            IRWAPriceNotificationDispatcher notificationDispatcher = IGetNotificationDispatcher(address(oracle)).notificationDispatcher();

            if (!INotificationWhitelister(address(notificationDispatcher)).whitelistedReceiver(address(newBasketBeacon))) {
                INotificationWhitelister(address(notificationDispatcher)).whitelistAddressAndReceiver(address(newBasketBeacon));
            }

            IERC721(_tangibleNFTDeposit[i]).transferFrom(msg.sender, address(this), _tokenIdDeposit[i]);
            IERC721(_tangibleNFTDeposit[i]).approve(address(newBasketBeacon), _tokenIdDeposit[i]);
        }

        // call batchDepositTNFT
        basketShares = IBasket(address(newBasketBeacon)).batchDepositTNFT(_tangibleNFTDeposit, _tokenIdDeposit);

        emit BasketCreated(msg.sender, address(newBasketBeacon));
        return (IBasket(address(newBasketBeacon)), basketShares);
    }

    /**
     * @notice This method allows the factory owner to update the `primaryRentToken` state variable.
     * @dev If the rent token is being changed indefinitely, make sure to change the address of the rent token being used
     *      to initialize new baskets on the BasketManager.
     * @param _primaryRentToken New address for `primaryRentToken`.
     */
    function updatePrimaryRentToken(address _primaryRentToken, bool _isRebaseToken) external onlyFactoryOwner {
        if (_primaryRentToken == address(0)) revert ZeroAddress();
        emit PrimaryRentTokenUpdated(_primaryRentToken);
        primaryRentToken = _primaryRentToken;
        rentIsRebaseToken = _isRebaseToken;
    }

    /**
     * @notice This method allows the factory owner to update the `rebaseController` state variable.
     * @param _controller New address for `rebaseController`.
     */
    function setRebaseController(address _controller) external onlyFactoryOwner {
        if (_controller == address(0)) revert ZeroAddress();
        emit RebaseControllerUpdated(_controller);
        rebaseController = _controller;
    }

    /**
     * @notice Withdraws any ERC20 token balance of this contract into the multisig wallet.
     * @param _contract Address of an ERC20 compliant token.
     */
    function withdrawERC20(address _contract) external onlyFactoryOwner {
        if (_contract == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(_contract).balanceOf(address(this));
        if (balance == 0) revert InsufficientBalance();

        IERC20(_contract).safeTransfer(msg.sender, balance);
    }

    /**
     * @notice This function allows the factory owner to update the Basket implementation.
     * @param _newBasketImp Address of new Basket contract implementation.
     */
    function updateBasketImplementation(address _newBasketImp) external onlyFactoryOwner {
        if (_newBasketImp == address(0)) revert ZeroAddress();
        emit BasketImplementationUpdated(_newBasketImp);
        beacon.upgradeTo(_newBasketImp);
    }

    /**
     * @notice This method allows the factory owner to update the `basketsVrfConsumer` contract address.
     * @param _basketsVrfConsumer New contract address.
     */
    function setBasketsVrfConsumer(address _basketsVrfConsumer) external onlyFactoryOwner {
        if (_basketsVrfConsumer == address(0)) revert ZeroAddress();
        emit BasketsVrfConsumerUpdated(_basketsVrfConsumer);
        basketsVrfConsumer = _basketsVrfConsumer;
    }

    /**
     * @notice This method allows the factory owner to update the `revenueDistributor` contract address.
     * @param _revenueDistributor New contract address.
     */
    function setRevenueDistributor(address _revenueDistributor) external onlyFactoryOwner {
        if (_revenueDistributor == address(0)) revert ZeroAddress();
        emit RevenueDistributorUpdated(_revenueDistributor);
        revenueDistributor = _revenueDistributor;
    }

    /**
     * @notice This method allows the factory owner to update the `currencyCalculator` contract address.
     * @param _currencyCalculator New contract address.
     */
    function setCurrencyCalculator(address _currencyCalculator) external onlyFactoryOwner {
        if (_currencyCalculator == address(0)) revert ZeroAddress();
        emit CurrencyCalculatorUpdated(_currencyCalculator);
        currencyCalculator = ICurrencyCalculator(_currencyCalculator);
    }

    /**
     * @notice This method allows the factory owner to update the limit of features a basket can support.
     * @param _limit New feature limit.
     */
    function setFeatureLimit(uint256 _limit) external onlyFactoryOwner {
        emit FeatureLimitUpdated(_limit);
        featureLimit = _limit;
    }

    /**
     * @notice View method for fetching baskets array.
     * @return baskets array.
     */
    function getBasketsArray() external view returns (address[] memory) {
        return baskets;
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @notice This method is used for querying whether a provided address is one of a basket.
     * @param _basket Address of basket.
     * @dev If true, `_basket` is a basket.
     */
    function isBasket(address _basket) public view returns (bool) {
        return getBasketInfo[_basket].isBasket;
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

    /**
     * @notice This internal method is to sanitize an array of features.
     * @dev This array will sanitize `_features` by ensuring it is both sorted and doesnt contain duplicates.
     * @param _features Array of features.
     * @return isSorted If true, `_features` is verified to be sorted and doesnt contain duplicates.
     */
    function _verifySortedNoDuplicates(uint256[] memory _features) internal pure returns (bool isSorted) {
        uint256 length = _features.length - 1;
        for (uint256 i; i < length; ++i) {
            // if greater-than => not sorted
            // if equal-to => duplicates
            if (_features[i] >= _features[i+1]) return false;
        }
        return true;
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the factory owner to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyFactoryOwner {}
}