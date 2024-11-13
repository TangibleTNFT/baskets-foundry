// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// tangible contract
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";
import { MockMatrixOracle } from "@tangible/tests/mocks/MockMatrixOracle.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { CurrencyCalculator } from "../src/CurrencyCalculator.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "../src/interfaces/IGetNotificationDispatcher.sol";
import { IUSTB } from "../src/interfaces/IUSTB.sol";

// local helper contracts
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";

contract RebaseTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public basket = Basket(0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48);

    /// @notice Config function for test cases.
    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 873405);
    }

    function test_UKRE_rebase() public {
        emit log_named_uint("totalRentValue", basket.totalRentValue()); // 11,284.751234746975806619
        emit log_named_uint("getrentBal", basket.getRentBal()); // 11967.643965160655615456
        emit log_named_uint("difference", basket.getRentBal()-basket.totalRentValue()); // 682.892730413679808837
        emit log_named_uint("total supply", basket.totalSupply()); // 22,675.572451056067655790
        emit log_named_uint("total supply * sharePrice", basket.totalSupply() * basket.getSharePrice() / 1e18); // 2,340,106.301753146975795410

        vm.rollFork(873407);

        emit log_named_uint("totalRentValue", basket.totalRentValue()); // 11,899.374856893481182957
        emit log_named_uint("total supply", basket.totalSupply()); // 22,681.410723130959240193
        emit log_named_uint("total supply * sharePrice", basket.totalSupply() * basket.getSharePrice() / 1e18); // 2,340,720.925375293481176421
    }
}