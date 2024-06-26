// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

// local
import { ICounterContract } from "./utils/Utility.sol";


/// @notice Counter helper contract for testing.
contract CounterContract is Initializable, ICounterContract {

    uint256 public counter;

    function initialize(uint256 _counterVar) external initializer {
        counter = _counterVar;
    }

    function increment() external {
        ++counter;
    }
}

/**
 * @title BeaconProxyTest
 * @author Chase Brown
 * @notice Testing file for testing beacon proxies.
 */
contract BeaconProxyTest is Test {

    CounterContract public counterContract;
    UpgradeableBeacon public beacon;
    
    function setUp() public {

        // deploy implementation contract.
        counterContract = new CounterContract();

        // deploy upgradeableBeacon.
        beacon = new UpgradeableBeacon(
            address(counterContract),
            address(this)
        );

        // Verify implementation for beacon is counterContract.
        assertEq(beacon.implementation(), address(counterContract));
        
    }


    // ~ Utility ~

    /// @notice Deploys new beacon.
    function _deployNewBeaconProxy(uint256 _initCounterVar) internal returns (BeaconProxy) {

        BeaconProxy newBeacon = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(CounterContract(address(0)).initialize.selector, 
                _initCounterVar
            )
        );

        return newBeacon;
    }


    // ~ Unit Tests ~

    function test_beaconProxy() public {

        // Deploy 2 beacons with different init variables.
        BeaconProxy beaconProxy1 = _deployNewBeaconProxy(111);
        BeaconProxy beaconProxy2 = _deployNewBeaconProxy(222);

        emit log_address(address(beaconProxy1));
        emit log_address(address(beaconProxy2));

        // Verify beaconProxy1 and beaconProxy2 have different contract addresses.
        assertNotEq(address(beaconProxy1), address(beaconProxy2));

        // Verify both beacons contain the correct init values for counter.
        assertEq(ICounterContract(address(beaconProxy1)).counter(), 111);
        assertEq(ICounterContract(address(beaconProxy2)).counter(), 222);

        // Increment beaconProxy1.
        ICounterContract(address(beaconProxy1)).increment();

        // Verify beaconProxy1 has incremented counter.
        assertEq(ICounterContract(address(beaconProxy1)).counter(), 112);
        assertEq(ICounterContract(address(beaconProxy2)).counter(), 222);

        // Increment beaconProxy2.
        ICounterContract(address(beaconProxy2)).increment();

        // Verify beaconProxy2 has incremented counter.
        assertEq(ICounterContract(address(beaconProxy1)).counter(), 112);
        assertEq(ICounterContract(address(beaconProxy2)).counter(), 223);
    }

}
