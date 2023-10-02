// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// local imports
import { Basket } from "./Basket.sol";
import { IBasket } from "./interfaces/IBasket.sol";
import { ArrayUtils } from "./libraries/ArrayUtils.sol";
import { UpgradeableBeacon } from "./proxy/UpgradeableBeacon.sol";
import { BasketBeaconProxy } from "./proxy/BasketBeaconProxy.sol";

// tangible imports
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol"; 


/**
 * @title BasketManager
 * @author Chase Brown
 * @notice This contract manages all Basket contracts.
 */
contract BasketManager is FactoryModifiers {
    using ArrayUtils for uint256[];

    // ~ State Variables ~
    // TODO: pack?

    /// @notice Mapping that stores the unique `featureHash` for each basket.
    mapping(address => bytes32) public hashedFeaturesForBasket;

    /// @notice Mapping that stores whether a specified address is a basket.
    mapping(address => bool) public isBasket;

    /// @notice UpgradeableBeacon contract instance. Deployed by this contract upon initialization.
    UpgradeableBeacon immutable public beacon;

    /// @notice Array of all baskets deployed.
    address[] public baskets;

    /// @notice Limit of amount of features allowed per basket.
    uint256 public featureLimit;

    /// @notice Contract address of basketsVrfConsumer contract.
    address public basketsVrfConsumer;

    // ~ Events ~

    /// @notice Emitted when a new basket instance is created // beaconProxy deployed.
    event BasketCreated(address creator, address basket);


    // ~ Modifiers ~

    /// @notice Modifier verifying msg.sender is a valid Basket contract.
    modifier onlyBasket() {
        require(isBasket[msg.sender], "Caller is not valid basket");
        _;
    }


    // ~ Constructor ~

    /**
     * @notice Initializes BasketManager contract. TODO: Update to initialize()
     * @param _initBasketImplementation Contract address of Basket implementation contract.
     * @param _factoryProvider Contract address of FactoryProvider contract.
     */
    constructor(address _initBasketImplementation, address _factoryProvider) FactoryModifiers(_factoryProvider) {
        __FactoryModifiers_init(_factoryProvider);
        beacon = new UpgradeableBeacon(_initBasketImplementation);

        featureLimit = 10; // TODO: Add setter
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
        address metadata = IFactory(IFactoryProvider(factoryProvider).factory()).tnftMetadata();
        (bool added,,) = ITNFTMetadata(metadata).tnftTypes(_tnftType);
        require(added, "Invalid tnftType");

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
            abi.encodeWithSelector(Basket(address(0)).initialize.selector, 
                _name,
                _symbol,
                factoryProvider,
                _tnftType,
                _rentToken,
                _features,
                msg.sender
            )
        );

        // store hash and new newBasketBeacon
        hashedFeaturesForBasket[address(newBasketBeacon)] = hashedFeatures;
        baskets.push(address(newBasketBeacon));
        isBasket[address(newBasketBeacon)] = true;

        // transfer initial TNFT from newBasketBeacon owner to this contract and approve transfer of TNFT to new basket
        for (uint256 i; i < _tokenIdDeposit.length;) {
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
     * @notice This method allows the factory owner to update the basketsVrfConsumer contract address.
     * @param _basketsVrfConsumer New contract address.
     */
    function setBasketsVrfConsumer(address _basketsVrfConsumer) external onlyFactoryOwner {
        require(_basketsVrfConsumer != address(0), "_basketsVrfConsumer == address(0)");
        basketsVrfConsumer = _basketsVrfConsumer;
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
     * @notice This method is used to create a unique hash given a category and list of sub categories.
     * @param _tnftType Category identifier.
     * @param _features List of subcategories.
     */
    function createHash(uint256 _tnftType, uint256[] memory _features) public pure returns (bytes32 hashedFeatures) {
        hashedFeatures = keccak256(abi.encodePacked(_tnftType, _features.sort()));
    }

    // NOTE for testing only
    function addBasket(address _basket) external onlyFactoryOwner {
        require(!isBasket[_basket], "Basket already exists");
        
        baskets.push(_basket);
        isBasket[address(_basket)] = true;
    }

    // TODO: remove (only kept it to not break existing tests)
    function sort(uint256[] memory arr) public pure returns (uint256[] memory) {
        return arr.sort();
    }

}
