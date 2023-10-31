// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// oz imports
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";

import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

import { ICounterContract } from "./utils/Utility.sol";


/// @notice Counter helper contract for testing.
contract CounterContract1 is Initializable, UUPSUpgradeable, ICounterContract {

    uint256 public counter;

    function initialize(uint256 _counterVar) external initializer {
        counter = _counterVar;
    }

    function increment() external {
        ++counter;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == address(222));
    }
}

/// @notice Counter helper contract for testing.
contract CounterContract2 is Initializable, UUPSUpgradeable, ICounterContract {

    uint256 public counter;

    function initialize(uint256 _counterVar) external initializer {
        counter = _counterVar;
    }

    function increment() external {
        counter = counter * 10;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == address(222));
    }
}


/**
 * @title BasicProxyTest
 * @author Chase Brown
 * @notice This test file contains basic unit tests for testing the use of the UUPSUpgradeable proxy implementation.
 */
contract BasicProxyTest is Utility {

    // ~ Contracts ~

    CounterContract1 public counterContract1;
    CounterContract2 public counterContract2;

    ERC1967Proxy public baseProxy;

    // ~ Actors and Variables ~


    /// @notice Config function for test cases.
    function setUp() public {

        // deploy implementations
        counterContract1 = new CounterContract1();
        counterContract2 = new CounterContract2();

        baseProxy = new ERC1967Proxy(
            address(counterContract1),
            abi.encodeWithSelector(CounterContract1.initialize.selector,
                1
            )
        );
        counterContract1 = CounterContract1(address(baseProxy));
    }

    /// @notice Initial state test.
    function test_proxy_init_state() public {
        assertEq(counterContract1.counter(), 1);
    }

    /// @notice Verifies use of `upgradeToAndCall`
    function test_proxy_upgrade() public {

        vm.prank(address(222));
        UUPSUpgradeable(address(baseProxy)).upgradeToAndCall(
            address(counterContract2), 
            ""
        );
        counterContract2 = CounterContract2(address(baseProxy));

        assertEq(counterContract2.counter(), 1);

        counterContract2.increment();

        assertEq(counterContract2.counter(), 10);
    }
    
}