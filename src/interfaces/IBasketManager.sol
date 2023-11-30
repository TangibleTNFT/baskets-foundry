// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IBasket } from "./IBasket.sol";

/// @title IBasketManager interface defines the interface of the BasketManager contract.
interface IBasketManager {

    function hashedFeaturesForBasket(address _basket) external returns (bytes32);

    function deployBasket(
        string memory _name,
        string memory _symbol,
        uint256 _tnftType,
        address _currencyFeed,
        address _rentToken,
        uint256[] memory _features
    ) external returns (IBasket);

    function updateFeaturesHash(bytes32 _newHash) external;

    function getBasketsArray() external returns (address[] memory);

    function checkBasketAvailability(bytes32 _hashToCheck) external returns (bool);

    function createHash(uint256 _tnftType, uint256[] memory _features) external pure returns (bytes32 hashedFeatures);

    function sort(uint[] memory data) external pure returns (uint[] memory);

    function isBasket(address _basket) external returns (bool);

    function basketsVrfConsumer() external returns (address);

    function revenueShare() external returns (address);
}