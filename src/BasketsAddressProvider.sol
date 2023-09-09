// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

/**
 * @title BasketAddressProvider
 * @notice This contract is used to store the BasketManager address.
 */
contract BasketAddressProvider is OwnableUpgradeable {
    
    // ~ State Variables ~

    /// @notice Stores address of BasketManager contract.
    address public basketManager;

    // ~ Events ~

    /// @notice This event is emitted when the `BasketManager` variable is updated.
    event BasketManagerSet(address oldBasketManager, address newBasketManager);

    // ~ Functions

    /**
     * @notice This function is used to initialize the contract.
     * @param _basketManager BasketManager address.
     */
    function initialize(address _basketManager) external initializer {
        __Ownable_init();
        basketManager = _basketManager;
    }

    /**
     * @notice This function is used to update the `basketManager` variable.
     * @param _basketManager BasketManager address to set.
     */
    function setBasketManager(address _basketManager) external onlyOwner {
        require(_basketManager != address(0), "Fac 0");
        emit BasketManagerSet(basketManager, _basketManager);
        basketManager = _basketManager;
    }
}
