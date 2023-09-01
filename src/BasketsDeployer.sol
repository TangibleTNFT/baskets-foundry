// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { Basket } from "./Baskets.sol";
import { IBasket } from "./IBaskets.sol";


contract BasketDeployer is FactoryModifiers {

    constructor(address _factoryProvider) FactoryModifiers(_factoryProvider) {}

    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType,
        address _currencyFeed,
        address _metadata
    ) external returns (IBasket) {
        require(msg.sender == IFactoryProvider(factoryProvider).factory(), "NF");
        Basket basket = new Basket(
            _name,
            _symbol,
            factoryProvider,
            _tnftType,
            _currencyFeed,
            _metadata
        );

        return IBasket(address(basket));
    }
}