// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { Basket } from "./Baskets.sol";
import { IBasket } from "./IBaskets.sol";


// TODO: Track all baskets deployed


contract BasketDeployer is FactoryModifiers {

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

    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType,
        address _currencyFeed,
        address _rentToken,
        uint256[] memory _features
    ) external returns (IBasket) {

        bytes32 hashedFeatures = keccak256(abi.encodePacked(_tnftType, sort(_features)));
        require(checkBasketAvailability(hashedFeatures), "Basket already exists");
        
        Basket basket = new Basket(
            _name,
            _symbol,
            factoryProvider,
            _tnftType,
            _currencyFeed,
            _rentToken,
            _features
        );

        hashedFeaturesForBasket[address(basket)] = hashedFeatures;
        baskets.push(address(basket));

        emit BasketCreated(msg.sender, address(basket));
        return IBasket(address(basket));
    }

    function updateFeaturesHash(bytes32 newFeaturesHash) external onlyBasket { // TODO: Test
        hashedFeaturesForBasket[msg.sender] = newFeaturesHash;
        emit HashedFeaturesForBasketUpdated(msg.sender, newFeaturesHash);
    }

    function getBasketsArray() external view returns (address[] memory) {
        return baskets;
    }

    function checkBasketAvailability(bytes32 featuresHash) public returns (bool) {
        for (uint256 i; i < baskets.length;) {
            if (hashedFeaturesForBasket[baskets[i]] == featuresHash) return false;
            unchecked {
                ++i;
            }
        }
        return true;
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
        }
        return (0, false);
    }


}