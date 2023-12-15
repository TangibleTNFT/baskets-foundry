// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";

// helper contracts
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

/// @dev To run: forge script script/mumbai/RedeemFromBasket.s.sol:RedeemFromBasket --fork-url <RPC_URL> --broadcast -vvvv

/**
 * @title RedeemFromBasket
 * @author Chase Brown
 * @notice This script allows a designated EOA to redeem from a mumbai basket.
 */
contract RedeemFromBasket is Script {

    // ~ Script Configure ~

    // baskets
    Basket public basket = Basket(Mumbai_Basket_1);

    // wallets
    address immutable DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    address deployerAddress;
    uint256 deployerPrivKey;

    function setUp() public {

        deployerAddress = DEPLOYER_ADDRESS;
        deployerPrivKey = DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        uint256 balance = basket.balanceOf(deployerAddress);

        console2.log("balance of basket tokens", balance);

        // 1. redeem from Basket
        basket.redeemTNFT(balance);

        vm.stopBroadcast();
    }
}
