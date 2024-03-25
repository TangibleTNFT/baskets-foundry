// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/// @dev To run: forge script script/unreal/ReadBasket.s.sol:ReadBasket --broadcast --legacy

/**
 * @title ReadBasket
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Unreal Testnet.
 */
contract ReadBasket is Script {

    // ~ Script Configure ~

    Basket public basket = Basket(0x1804C32c5495643998B70C311AB461AE348a7FEe);

    // wallets
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    uint256 deployerPrivKey;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);

        deployerPrivKey = DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        uint256 price = basket.getSharePrice();
        console2.log("basket share price =", price);

        uint256 totalSupply = basket.totalSupply();
        console2.log("basket totalSupply =", totalSupply);

        uint256 totalValue = basket.getTotalValueOfBasket();
        console2.log("basket total value =", totalValue);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();

        console2.log("length", deposited.length);

        console2.log("tnft", deposited[0].tnft);
        console2.log("tokenId", deposited[0].tokenId);
        console2.log("FP", deposited[0].fingerprint);
        console2.log("value", basket.valueTracker(deposited[0].tnft, deposited[0].tokenId));

        console2.log("tnft", deposited[1].tnft);
        console2.log("tokenId", deposited[1].tokenId);
        console2.log("FP", deposited[1].fingerprint);
        console2.log("value", basket.valueTracker(deposited[1].tnft, deposited[1].tokenId));
        
        vm.stopBroadcast();
    }
}

// price = 100.672599029097028712
// total Supply = 2346.015792556800000000
// total value = 236179.507200000000000000

// mint = 80,000 * 2345.0158 / 236179.5072
// mint = 794.316434
// penalty = 3.971582
// mint after penalty = 790.344852

// new price = (2345.0158 + 790.344852) / (236179.5072 + 80,000) = 100.843106
// value = 790.344852 * 100.843106 = 79700.829686