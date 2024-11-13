// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// chainlink imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// local contracts
import { Basket } from "../src/Basket.sol";

// local helper contracts
import "./utils/Re.alAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title BasketPriceHistorical
 * @author Chase Brown
 * @notice This test file contains integration tests for the wrapped baskets token.
 */
contract BasketPriceHistorical is Utility {

    // ~ Contracts ~

    // baskets
    Basket public UKRE = Basket(0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48); // re.al UKRE
    AggregatorV3Interface public oracle = AggregatorV3Interface(0x100c8e61aB3BeA812A42976199Fc3daFbcDD7272); // gbp/usd oracle

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL); // July 16th 2024 @9:37am
    }

    function test_historical() public {
        UKRE.getDepositedTnfts();
        
        emit log_named_uint("current price", UKRE.getSharePrice()); // 100.1122
        emit log_named_uint("current totalValue", UKRE.getTotalValueOfBasket()); // 92_959.57
        emit log_named_uint("current home value", UKRE.totalNftValueByCurrency("GBP")); // 70_904.200
        emit log_named_uint("current rentBal", UKRE.getRentBal()); // 489.15
        (, int256 price,,,) = oracle.latestRoundData();
        emit log_named_uint("current exchange rate", uint256(price)); // 1.29416000

        vm.rollFork(77398); // roll to ~60 days ago

        emit log_named_uint("old price", UKRE.getSharePrice()); // 100.6083
        emit log_named_uint("old totalValue", UKRE.getTotalValueOfBasket()); // 92_930.79
        emit log_named_uint("old home value", UKRE.totalNftValueByCurrency("GBP")); // 72_404.200
        emit log_named_uint("old rentBal", UKRE.getRentBal()); // 0
        (, price,,,) = oracle.latestRoundData();
        emit log_named_uint("old exchange rate", uint256(price)); // 1.27350000
    }
}