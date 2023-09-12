// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { Basket } from "./Baskets.sol";
import { IBasket } from "./interfaces/IBaskets.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


/**
 * @title BasketManager
 * @author Chase Brown
 * @notice This contract manages all deployed Basket contracts.
 */
contract BasketManager is FactoryModifiers {

    // ~ State Variables ~

    address[] public baskets;

    mapping(address => bytes32) public hashedFeaturesForBasket;


    // ~ Events ~

    event BasketCreated(address creator, address basket);

    event HashedFeaturesForBasketUpdated(address basket, bytes32 hashedFeatures);


    // ~ Modifiers ~

    modifier onlyBasket() {
        (,bool exists) = _isBasket(msg.sender);
        require(exists, "Caller is not valid basket");
        _;
    }


    // ~ Constructor ~

    constructor(address _factoryProvider) FactoryModifiers(_factoryProvider) {}


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
        address _tangibleNFTDeposit,
        uint256 _tokenIdDeposit
    ) external returns (IBasket, uint256 basketShare) {

        // create hash
        bytes32 hashedFeatures = createHash(_tnftType, _features);

        // might not be necessary -> hash is checked when Basket is initialized
        require(checkBasketAvailability(hashedFeatures), "Basket already exists");

        // transfer initial TNFT from basket owner to this contract
        IERC721(_tangibleNFTDeposit).safeTransferFrom(msg.sender, address(this), _tokenIdDeposit);
        
        // create new basket
        Basket basket = new Basket(
            _name,
            _symbol,
            factoryProvider,
            _tnftType,
            _rentToken,
            _features,
            msg.sender
        );

        // approve transfer of TNFT to new basket and call depositTNFT
        IERC721(_tangibleNFTDeposit).approve(address(basket), _tokenIdDeposit);
        basketShare = basket.depositTNFT(_tangibleNFTDeposit, _tokenIdDeposit);

        // store hash and new basket
        hashedFeaturesForBasket[address(basket)] = hashedFeatures;
        baskets.push(address(basket));

        emit BasketCreated(msg.sender, address(basket));
        return (IBasket(address(basket)), basketShare);
    }

    function updateFeaturesHash(bytes32 newFeaturesHash) external onlyBasket { // TODO: Test
        hashedFeaturesForBasket[msg.sender] = newFeaturesHash;
        emit HashedFeaturesForBasketUpdated(msg.sender, newFeaturesHash);
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

    function checkBasketAvailability(bytes32 featuresHash) public view returns (bool) {
        for (uint256 i; i < baskets.length;) {
            if (hashedFeaturesForBasket[baskets[i]] == featuresHash) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    function createHash(uint256 _tnftType, uint256[] memory _features) public pure returns (bytes32 hashedFeatures) {
        if (_features.length > 1) {
            hashedFeatures = keccak256(abi.encodePacked(_tnftType, sort(_features)));
        } else {
            hashedFeatures = keccak256(abi.encodePacked(_tnftType, _features));
        }
    }

    function addBasket(address _basket) external onlyFactoryOwner {
        (,bool exists) = _isBasket(_basket);
        require(!exists);
        baskets.push(_basket);
    }

    function sort(uint[] memory data) public pure returns (uint[] memory) {
        _sort(data, int(0), int(data.length - 1));
        return data;
    }

    function _sort(uint[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;

        uint pivot = arr[uint(left + (right - left) / 2)];

        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }

        if (left < j)
            _sort(arr, left, j);
        if (i < right)
            _sort(arr, i, right);
    }

    function _isBasket(address basket) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < baskets.length;) {
            if (baskets[i] == basket) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }


}