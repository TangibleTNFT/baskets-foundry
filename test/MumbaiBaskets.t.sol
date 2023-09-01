// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// local contracts
import { Basket } from "../src/Baskets.sol";
import { BasketDeployer } from "../src/BasketsDeployer.sol";
import "./MumbaiAddresses.sol";

// tangible contract imports
import { FactoryProvider } from "@tangible/FactoryProvider.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";
import { IMarketplace } from "@tangible/interfaces/IMarketplace.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


// Mumbai RPC: https://rpc.ankr.com/polygon_mumbai

interface ITangibleNFTExt is ITangibleNFT {
    /// @dev Returns the feature status of a `tokenId`.
    function tokenFeatureAdded (uint256 tokenId, uint256 feature) external view returns (FeatureInfo memory);
    function getFingerprintsSize() external view returns (uint256);
    function getFingerprints() external view returns (uint256[] memory);
}

interface IPriceOracleExt {
    function updateStock(uint256 fingerprint, uint256 weSellAtStock) external;
    function setTangibleWrapperAddress(address oracle) external;
    function createItem(
        uint256 fingerprint,
        uint256 weSellAt,
        uint256 lockedAmount,
        uint256 weSellAtStock,
        uint16 currency,
        uint16 location
    ) external;
}

interface IFactoryExt {
    function setRequireWhitelistCategory(ITangibleNFT tnft, bool required) external;
}

interface IPriceManagerExt {
    function oracleForCategory(ITangibleNFT) external returns (IPriceOracle);
}

contract MumbaiBasketsTest is Test {
    Basket public basket;
    BasketDeployer public basketDeployer;
    //FactoryProvider public factoryProvider;

    //contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_ChainlinkOracle);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    IFactoryProvider public factoryProvider = IFactoryProvider(Mumbai_FactoryProvider);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Mumbai_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Mumbai_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);


    // Actors
    address public constant JOE = address(bytes20(bytes("Joe")));
    address public constant ADMIN = address(bytes20(bytes("Admin")));
    //address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible Labs Multisig")));

    address public factoryOwner = IOwnable(address(factoryV2)).contractOwner();
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;

    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4;

    uint256 public constant RE_TNFTTYPE = 2;
    uint256 public constant RE_FINGERPRINT_1 = 2032;
    uint256 public constant RE_FINGERPRINT_2 = 2033;
    uint256 public constant RE_FINGERPRINT_3 = 2034;
    uint256 public constant RE_FINGERPRINT_4 = 2084;
    
    uint256 public constant GOLD_TNFTTYPE = 1;

    function setUp() public {

        // Deploy Basket
        basket = new Basket(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            RE_TNFTTYPE,
            address(currencyFeed),
            address(metadata)
        );

        vm.startPrank(ORACLE_OWNER);
        // set tangibleWrapper to be real estate oracle.
        IPriceOracleExt(address(chainlinkRWAOracle)).setTangibleWrapperAddress(
            address(realEstateOracle)
        );
        // fingerprint create new item with fingerprint.
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            RE_FINGERPRINT_1,  // fingerprint
            500_000_000,     // weSellAt
            0,            // lockedAmount
            2,            // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            RE_FINGERPRINT_2,  // fingerprint
            600_000_000,     // weSellAt
            0,            // lockedAmount
            1,            // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        vm.stopPrank();

        // create mint voucher
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            40000000,                               // price     // TODO: Verify
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_1,                       // fingerprint
            true                                    // sendToVender
        );

        // mint fingerprint RE_1
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        vm.prank(TANGIBLE_LABS);
        factoryV2.mint(voucher);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 1);

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(JOE), 1);

        // labels
        vm.label(address(factoryV2), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(chainlinkRWAOracle), "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(factoryProvider), "FACTORY_PROVIDER");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(basket), "BASKET");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
    }

    // ~ Utility ~

    function _emitGetUsdValueOfNft(address _tnft, uint256 _tokenId) internal {
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        emit log_named_uint("fingerprint", fingerprint);

        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = realEstateOracle.marketPriceNativeCurrency(fingerprint);
        emit log_named_uint("market value", value);
        emit log_named_uint("currencyNum", currencyNum);

        // Fetch the string ISO code for currency
        string memory currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));
        emit log_named_string("currencyAlpha", currency);

        // get decimal representation of property value
        uint256 oracleDecimals = realEstateOracle.decimals();
        emit log_named_uint("oracle decimals", oracleDecimals);
        
        // ~ get USD Exchange rate ~

        // fetch price feed contract for native currency
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currency);
        emit log_named_address("address of priceFeed", address(priceFeed));

        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();
        emit log_named_uint("Price of GBP/USD", uint(price));

        // get decimal representation of exchange rate
        uint256 priceDecimals = priceFeed.decimals();
        emit log_named_uint("price feed decimals", priceDecimals);
 
        // ~ get USD Value of property ~

        // calculate total USD value of property
        uint256 UsdValue = (uint(price) * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
        emit log_named_uint("USD Value", UsdValue);

    }


    // ~ Initial State Test ~

    /// @notice Initial state test.
    function test_mumbai_init_state() public {
        // verify realEstateTnft
        assertEq(realEstateTnft.tokensFingerprint(1), RE_FINGERPRINT_1); // 2032

        // verify factoryProvider has correct factory
        assertEq(factoryProvider.factory(), address(factoryV2));

        // verify factoryV2 has correct priceManager
        assertEq(address(factoryV2.priceManager()), address(priceManager));

        // verify priceManager has oracle set
        assertEq(address(IPriceManagerExt(address(priceManager)).oracleForCategory(realEstateTnft)), address(realEstateOracle));
    }


    // ~ Unit Tests ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_mumbai_depositTNFT() public {

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);
        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        // Execute a deposit
        _emitGetUsdValueOfNft(address(realEstateTnft), 1);

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));

        // Post-state check
        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);
        assertGt(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);
        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
    }

    // TODO: Test addFeatureSupport

    function test_mumbai_addFeatureSupport() public {
        uint256 _feature = 111;

        // Pre-state check.
        assertEq(basket.featureSupported(_feature), false);
        uint256[] memory features = basket.getFeaturesSupported();
        assertEq(features.length, 0);

        // Execute addFeatureSupport
        basket.addFeatureSupport(_feature);

        // Post-state check.
        assertEq(basket.featureSupported(_feature), true);
        features = basket.getFeaturesSupported();
        assertEq(features.length, 1);
        assertEq(features[0], _feature);
    }

    // TODO: Test removeFeatureSupport
    // TODO: Test modifyRentTokenSupport

}