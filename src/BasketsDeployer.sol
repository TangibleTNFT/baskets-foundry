// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { Basket } from "./Baskets.sol";
import { IBasket } from "./IBaskets.sol";


// TODO: Track all baskets deployed


contract BasketDeployer is FactoryModifiers {

    constructor(address _factoryProvider) FactoryModifiers(_factoryProvider) {}

    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType, // TODO: Ability to add features in constructor -> Array, but optional
        address _currencyFeed,
        address _rentToken,
        uint256[] memory _features
    ) external returns (IBasket) {
        require(msg.sender == IFactoryProvider(factoryProvider).factory(), "NF"); // TODO: Remove
        Basket basket = new Basket(
            _name,
            _symbol,
            factoryProvider,
            _tnftType,
            _currencyFeed,
            _rentToken,
            _features
        );

        return IBasket(address(basket));
    }
}