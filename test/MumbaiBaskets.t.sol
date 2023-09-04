// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// local contracts
import { Basket } from "../src/Baskets.sol";
import { BasketDeployer } from "../src/BasketsDeployer.sol";
import "./MumbaiAddresses.sol";
import "./Utility.sol";

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

contract MumbaiBasketsTest is Test {

    Basket public basket;
    BasketDeployer public basketDeployer;

    //contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    //IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_ChainlinkOracle);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    IFactoryProvider public factoryProvider = IFactoryProvider(Mumbai_FactoryProvider);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Mumbai_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Mumbai_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);

    // ~ Actors ~

    address public constant JOE = address(bytes20(bytes("Joe")));
    address public constant NIK = address(bytes20(bytes("Nik")));

    address public factoryOwner = IOwnable(address(factoryV2)).contractOwner();
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4;

    // ~ Types and Features ~

    uint256 public constant RE_TNFTTYPE = 2;

    uint256 public constant RE_FINGERPRINT_1 = 2032;
    uint256 public constant RE_FINGERPRINT_2 = 2033;
    uint256 public constant RE_FINGERPRINT_3 = 2034;
    uint256 public constant RE_FINGERPRINT_4 = 2084;

    uint256 public constant RE_FEATURE_1 = 5555;
    uint256 public constant RE_FEATURE_2 = 4444;
    
    uint256 public constant GOLD_TNFTTYPE = 1;
    
    event log_named_bool(string key, bool val);

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
        // set tangibleWrapper to be real estate oracle on chainlink oracle.
        IPriceOracleExt(address(chainlinkRWAOracle)).setTangibleWrapperAddress(
            address(realEstateOracle)
        );
        // create new item with fingerprint.
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            RE_FINGERPRINT_1,  // fingerprint
            500_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            RE_FINGERPRINT_2,  // fingerprint
            600_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        vm.stopPrank();

        vm.startPrank(factoryOwner);
        // add feature to metadata contract
        ITNFTMetadataExt(address(metadata)).addFeatures(
            _asSingletonArrayUint(RE_FEATURE_1),
            _asSingletonArrayString("Beach Homes")
        );
        // add feature to TNFTtype in metadata contract
        ITNFTMetadataExt(address(metadata)).addFeaturesForTNFTType(
            RE_TNFTTYPE,
            _asSingletonArrayUint(RE_FEATURE_1)
        );
        vm.stopPrank();

        // create mint voucher for RE_FP_1
        IVoucher.MintVoucher memory voucher1 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_1,                       // fingerprint
            true                                    // sendToVender
        );

        // create mint voucher for RE_FP_2
        IVoucher.MintVoucher memory voucher2 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_2,                       // fingerprint
            true                                    // sendToVender
        );

        emit log_named_address("Oracle for category", address(priceManager.oracleForCategory(realEstateTnft)));

        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1), true);
        emit log_named_bool("Fingerprint added:", (ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1)));

        // mint fingerprint RE_1 and RE_2
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        vm.prank(TANGIBLE_LABS);
        factoryV2.mint(voucher1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 1);
        vm.prank(TANGIBLE_LABS);
        factoryV2.mint(voucher2);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 2);

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(JOE), 1);

        // transfer token to NIK
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, NIK, 2);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(NIK), 1);

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

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayString(string memory element) private pure returns (string[] memory) {
        string[] memory array = new string[](1);
        array[0] = element;

        return array;
    }

    /// @notice This method adds feature metadata to a tokenId on a tnft contract
    function _addFeatureToCategory(address _tnft, uint256 _tokenId, uint256 _feature) public {
        vm.prank(TANGIBLE_LABS);
        // add feature to tnft contract
        ITangibleNFTExt(_tnft).addMetadata(
            _tokenId,
            _asSingletonArrayUint(_feature)
        );
    }

    /// @notice This method runs through the same USDValue logic as the Basket::depositTNFT
    function _emitGetUsdValueOfNft(address _tnft, uint256 _tokenId) internal returns (uint256 UsdValue) {
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        //emit log_named_uint("fingerprint", fingerprint);

        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = realEstateOracle.marketPriceNativeCurrency(fingerprint);
        emit log_named_uint("market value", value);
        //emit log_named_uint("currencyNum", currencyNum);

        // Fetch the string ISO code for currency
        string memory currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));
        //emit log_named_string("currencyAlpha", currency);

        // get decimal representation of property value
        uint256 oracleDecimals = realEstateOracle.decimals();
        //emit log_named_uint("oracle decimals", oracleDecimals);
        
        // ~ get USD Exchange rate ~

        // fetch price feed contract for native currency
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currency);
        emit log_named_address("address of priceFeed", address(priceFeed));

        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();
        emit log_named_uint("Price of GBP/USD", uint(price));

        // get decimal representation of exchange rate
        uint256 priceDecimals = priceFeed.decimals();
        //emit log_named_uint("price feed decimals", priceDecimals);
 
        // ~ get USD Value of property ~

        // calculate total USD value of property
        UsdValue = (uint(price) * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
        emit log_named_uint("USD Value", UsdValue);

    }


    // ~ Initial State Test ~

    /// @notice Initial state test. TODO: Add more asserts
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


    // Note: Deposit Functionality ----

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_mumbai_depositTNFT_single() public {

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        // emit deposit logic 
        uint256 usdValue = _emitGetUsdValueOfNft(address(realEstateTnft), 1);
        uint256 sharePrice = basket.getSharePrice();

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        // Execute a deposit
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", sharePrice);

        // Post-state check
        assertEq(
            (basket.balanceOf(JOE) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_mumbai_depositTNFT_multiple() public {

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(NIK), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        // emit deposit logic 
        uint256 usdValue1 = _emitGetUsdValueOfNft(address(realEstateTnft), 1);
        uint256 usdValue2 = _emitGetUsdValueOfNft(address(realEstateTnft), 2);
        uint256 sharePrice = basket.getSharePrice();

        // Joe deposits TNFT
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Nik deposits TNFT
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), 2);
        basket.depositTNFT(address(realEstateTnft), 2);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("NIK's BASKET BALANCE", basket.balanceOf(NIK));
        emit log_named_uint("SHARE PRICE", sharePrice);

        // Post-state check
        assertEq(
            ((basket.balanceOf(JOE) + basket.balanceOf(NIK)) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(NIK), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 2);

        assertEq(basket.balanceOf(JOE), usdValue1);
        assertEq(basket.balanceOf(NIK), usdValue2);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, 2);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_mumbai_depositTNFT_feature() public {
        basket.addFeatureSupport(RE_FEATURE_1);

        // Pre-state check
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(basket.featureSupported(RE_FEATURE_1), true);

        // Execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        vm.expectRevert("TNFT missing feature");
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(basket.featureSupported(RE_FEATURE_1), true);

        // add feature to TNFT
        _addFeatureToCategory(address(realEstateTnft), 1, RE_FEATURE_1);

        // Execute a deposit
        vm.startPrank(JOE);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(basket.featureSupported(RE_FEATURE_1), true);
    }


    // Note: Feature Management ----

    /// @notice This verifies state changes and restrictions for addFeatureSupport()
    function test_mumbai_addFeatureSupport() public {

        // Pre-state check.
        assertEq(basket.featureSupported(RE_FEATURE_1), false);
        assertEq(basket.activelySupportingFeature(), false);

        // Execute addFeatureSupport
        basket.addFeatureSupport(RE_FEATURE_1);

        // Post-state check.
        assertEq(basket.featureSupported(RE_FEATURE_1), true);
        assertEq(basket.activelySupportingFeature(), true);

        // Try to add another feature -> revert
        vm.expectRevert("Feature already supported");
        basket.addFeatureSupport(RE_FEATURE_2);
    }

    /// @notice This verifies state changes and restrictions for addFeatureSupport()
    function test_mumbai_addFeatureSupport_afterDeposit() public {

        // Pre-state check.
        assertEq(basket.featureSupported(RE_FEATURE_1), false);

        // Joe makes deposit of TNFT
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Add feature whilst basket holds incompatible TNFT - > reverts
        vm.expectRevert("Incompatible TNFT in Basket");
        basket.addFeatureSupport(RE_FEATURE_1);

        // Post-state check 1.
        assertEq(basket.featureSupported(RE_FEATURE_1), false);

        // Add feature to TNFT contract
        _addFeatureToCategory(address(realEstateTnft), 1, RE_FEATURE_1);

        // Verify feature was added to TNFT
        uint256[] memory features = ITangibleNFT(address(realEstateTnft)).getTokenFeatures(1);
        emit log_named_uint("features", features[0]);
        assertEq(features[0], RE_FEATURE_1);

        // Add feature -> success
        basket.addFeatureSupport(RE_FEATURE_1);

        // Post-state check 2.
        assertEq(basket.featureSupported(RE_FEATURE_1), true);
    }

    /// @notice This verifies state changes and restrictions for removeFeatureSupport()
    function test_mumbai_removeFeatureSupport() public {
        basket.addFeatureSupport(RE_FEATURE_1);

        // Pre-state check.
        assertEq(basket.featureSupported(RE_FEATURE_1), true);
        assertEq(basket.activelySupportingFeature(), true);

        // Execute removeFeatureSupport
        basket.removeFeatureSupport(RE_FEATURE_1);

        // Post-state check.
        assertEq(basket.featureSupported(RE_FEATURE_1), false);
        assertEq(basket.activelySupportingFeature(), false);

        // Try to remove feature again -> revert
        vm.expectRevert("Feature not supported");
        basket.removeFeatureSupport(RE_FEATURE_1);
    }


    // Note: Rent Management ----

    /// @notice This verifies state changes and restrictions for modifyRentTokenSupport()
    function test_mumbai_modifyRentTokenSupport() public {
        // Pre-state check.
        address[] memory rentTokens = basket.getSupportedRentTokens();
        assertEq(rentTokens.length, 0);

        // Remove token -> revert
        vm.prank(factoryOwner);
        vm.expectRevert("Not supported");
        basket.modifyRentTokenSupport(USDC, false);

        // Add token -> Success
        vm.prank(factoryOwner);
        basket.modifyRentTokenSupport(USDC, true);

        // Post-state check.
        rentTokens = basket.getSupportedRentTokens();
        assertEq(rentTokens.length, 1);
        assertEq(rentTokens[0], USDC);

        // Add token again -> revert
        vm.prank(factoryOwner);
        vm.expectRevert("Already supported");
        basket.modifyRentTokenSupport(USDC, true);
    }

}