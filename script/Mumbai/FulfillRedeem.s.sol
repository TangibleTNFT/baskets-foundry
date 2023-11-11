// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// local contracts
import { VRFCoordinatorV2Mock } from "../../test/utils/VRFCoordinatorV2Mock.sol";

// helper contracts
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

/// @dev To run: forge script script/mumbai/FulfillRedeem.s.sol:FulfillRedeem --fork-url <RPC_URL> --broadcast -vvvv

/**
 * @title RedeemFromBasket
 * @author Chase Brown
 * @notice This script allows a designated EOA to redeem from a mumbai basket.
 */
contract FulfillRedeem is Script {

    // ~ Dev config ~

    // TODO
    uint64 public requestId = 2;

    // ~ Script Configure ~

    // baskets
    VRFCoordinatorV2Mock public vrfCoordinator = VRFCoordinatorV2Mock(Mumbai_MockVrfCoordinator);
    address public vrfConsumer = Mumbai_BasketVrfConsumer;

    // wallets
    address immutable MUMBAI_DEPLOYER_ADDRESS = vm.envAddress("MUMBAI_DEPLOYER_ADDRESS");
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");

    address deployerAddress;
    uint256 deployerPrivKey;

    function setUp() public {

        deployerAddress = MUMBAI_DEPLOYER_ADDRESS;
        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. redeem from Basket
        vrfCoordinator.fulfillRandomWords(requestId, vrfConsumer);

        vm.stopBroadcast();
    }
}
