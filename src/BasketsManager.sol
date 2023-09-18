// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// local
import { Basket } from "./Baskets.sol";
import { IBasket } from "./interfaces/IBaskets.sol";
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


/**
 * @title BasketManager
 * @author Chase Brown
 * @notice This contract manages all deployed Basket contracts.
 */
contract BasketManager is FactoryModifiers {
    using ArrayUtils for uint256[];

    // ~ State Variables ~

    UpgradeableBeacon immutable beacon;

    address[] public baskets;

    mapping(address => bytes32) public hashedFeaturesForBasket;

    mapping(address => bool) public isBasket;

    uint256 public featureLimit;


    // ~ Events ~

    event BasketCreated(address creator, address basket);


    // ~ Modifiers ~

    modifier onlyBasket() {
        require(isBasket[msg.sender], "Caller is not valid basket");
        _;
    }


    // ~ Constructor ~

    constructor(address _initBasketImplementation, address _factoryProvider) FactoryModifiers(_factoryProvider) {
        __FactoryModifiers_init(_factoryProvider);
        beacon = new UpgradeableBeacon(_initBasketImplementation);
        featureLimit = 10; // TODO: Add setter
    }


    // ~ Functions ~

    /**
     * @notice This method deploys a new Basket contract.
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
        require(_tangibleNFTDeposit.length == _tokenIdDeposit.length, "Differing lengths");

        address metadata = IFactory(IFactoryProvider(factoryProvider).factory()).tnftMetadata();
        (bool added,,) = ITNFTMetadata(metadata).tnftTypes(_tnftType);
        require(added, "Invalid tnftType");

        // create hash
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

    function getBasketsArray() external view returns (address[] memory) {
        return baskets;
    }

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function checkBasketAvailability(bytes32 _featuresHash) public view returns (bool) {
        for (uint256 i; i < baskets.length;) {
            if (hashedFeaturesForBasket[baskets[i]] == _featuresHash) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    function createHash(uint256 _tnftType, uint256[] memory _features) public pure returns (bytes32 hashedFeatures) {
        hashedFeatures = keccak256(abi.encodePacked(_tnftType, _features.sort()));
    }

    function addBasket(address _basket) external onlyFactoryOwner {
        require(!isBasket[_basket], "Basket already exists");
        
        baskets.push(_basket);
        isBasket[address(_basket)] = true;
    }

    // TODO: remove (only kept it to not break existing tests)
    function sort(uint256[] memory arr) public pure returns (uint256[] memory) {
        return arr.sort();
    }

    function _isBasket(address _basket) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < baskets.length;) {
            if (baskets[i] == _basket) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }


}
