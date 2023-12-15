// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

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
    uint64 public requestId = 3;

    // ~ Script Configure ~

    // baskets
    //VRFCoordinatorV2Mock public vrfCoordinator = VRFCoordinatorV2Mock(Mumbai_MockVrfCoordinator);
    address public vrfConsumer = Mumbai_BasketVrfConsumer;

    // wallets
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");

    uint256 deployerPrivKey;

    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);

        deployerPrivKey = DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. redeem from Basket
        //vrfCoordinator.fulfillRandomWords(requestId, vrfConsumer);

        vm.stopBroadcast();
    }
}
