// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/**
 * @dev This is a custom contract. It adds 2 helper methods to the BeaconProxy pattern.
 * This makes testing state easier when we're able to pull beacon data from the proxy.
 */
contract BasketBeaconProxy is BeaconProxy {

    /**
     * @dev Initializes the proxy with `beacon`.
     *
     * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
     * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
     * constructor.
     *
     * Requirements:
     *
     * - `beacon` must be a contract with the interface {IBeacon}.
     * - If `data` is empty, `msg.value` must be zero.
     */
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) payable {}
}