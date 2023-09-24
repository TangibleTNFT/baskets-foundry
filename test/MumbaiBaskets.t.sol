// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// local contracts
import { Basket } from "../src/Baskets.sol";
import { IBasket } from "../src/interfaces/IBaskets.sol";
import { BasketManager } from "../src/BasketsManager.sol";

import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

// tangible contract imports
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";

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
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


// Mumbai RPC: https://rpc.ankr.com/polygon_mumbai

contract MumbaiBasketsTest is Utility {

    Basket public basket;
    BasketManager public basketManager;

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
    IRentManager public rentManager = IRentManager(Mumbai_RentManagerTnft);

    // ~ Actors ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4; // NOTE: category owner

    address public rentManagerDepositor = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;
    
    event log_named_bool(string key, bool val);

    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).contractOwner();

        basket = new Basket();
        basketManager = new BasketManager(address(basket), address(factoryProvider));

        uint256[] memory features = new uint256[](0);

        // updateDepositor for rent manager
        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(TANGIBLE_LABS);

        // set basketManager
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // set currencyFeed
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        // Deploy Basket
        vm.prank(address(basket)); // TODO: Should be proxy
        basket.initialize( 
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        // add basket to basketManager
        vm.prank(factoryOwner);
        basketManager.addBasket(address(basket));

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
        vm.label(JOE, "JOE");
        vm.label(NIK, "NIK");
    }


    // -------
    // Utility
    // -------

    /// @notice This method adds feature metadata to a tokenId on a tnft contract
    function _addFeatureToCategory(address _tnft, uint256 _tokenId, uint256[] memory _features) public {
        vm.prank(TANGIBLE_LABS);
        // add feature to tnft contract
        ITangibleNFTExt(_tnft).addMetadata(
            _tokenId,
            _features
        );
    }

    /// @notice This method runs through the same USDValue logic as the Basket::depositTNFT
    function _getUsdValueOfNft(address _tnft, uint256 _tokenId) internal returns (uint256 UsdValue) {
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        //emit log_named_uint("fingerprint", fingerprint);

        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = realEstateOracle.marketPriceNativeCurrency(fingerprint);
        emit log_named_uint("market value", value); // 500_000_000
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
        emit log_named_uint("USD Value", UsdValue); // 650_000_000000000000000000 (18)

    }

    function _createItemAndMint(address tnft, uint256 _sellAt, uint256 _stock, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        require(_mintCount >= _stock, "mint count must be gt stock");

        vm.startPrank(ORACLE_OWNER);
        // create new item with fingerprint.
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            _fingerprint, // fingerprint
            _sellAt,      // weSellAt
            0,            // lockedAmount
            _stock,       // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        vm.stopPrank();

        vm.prank(TANGIBLE_LABS);
        ITangibleNFTExt(tnft).addFingerprints(_asSingletonArrayUint(_fingerprint));

        return _mintToken(tnft, _mintCount, _fingerprint, _receiver);
    }

    function _mintToken(address tnft, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        uint256 preBal = IERC721(tnft).balanceOf(TANGIBLE_LABS);

        // create mint voucher for RE_FP_1
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(tnft),  // token
            _mintCount,          // mintCount
            0,                   // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,       // vendor
            address(0),          // buyer
            _fingerprint,        // fingerprint
            true                 // sendToVender
        );

        // mint token
        vm.prank(TANGIBLE_LABS);
        uint256[] memory tokenIds = factoryV2.mint(voucher);
        assertEq(IERC721(tnft).balanceOf(TANGIBLE_LABS), preBal + _mintCount);

        // transfer token to NIK
        for (uint256 i; i < _mintCount; ++i) {
            vm.prank(TANGIBLE_LABS);
            IERC721(tnft).transferFrom(TANGIBLE_LABS, _receiver, tokenIds[i]);
        }
        assertEq(IERC721(tnft).balanceOf(TANGIBLE_LABS), preBal);

        return tokenIds;
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test. TODO: Add more asserts
    function test_baskets_mumbai_init_state() public {
        // verify realEstateTnft
        assertEq(realEstateTnft.tokensFingerprint(1), RE_FINGERPRINT_1); // 2032

        // verify factoryProvider has correct factory
        assertEq(factoryProvider.factory(), address(factoryV2));

        // verify factoryV2 has correct priceManager
        assertEq(address(factoryV2.priceManager()), address(priceManager));

        // verify priceManager has oracle set
        assertEq(address(IPriceManagerExt(address(priceManager)).oracleForCategory(realEstateTnft)), address(realEstateOracle));
    }


    // ----------
    // Unit Tests
    // ----------


    // ~ Deposit Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_mumbai_depositTNFT_single() public {

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // emit deposit logic 
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), 1);
        uint256 sharePrice = basket.getSharePrice();

        // Execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
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
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        uint256[] memory tokenidLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenidLib.length, 1);
        assertEq(tokenidLib[0], 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_mumbai_depositTNFT_multiple() public {

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

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // emit deposit logic 
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), 1);
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), 2);
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
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, 2);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_2);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        uint256[] memory tokenidLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenidLib.length, 2);
        assertEq(tokenidLib[0], 1);
        assertEq(tokenidLib[1], 2);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_mumbai_depositTNFT_feature() public {

        uint256[] memory features = new uint256[](1);
        features[0] = RE_FEATURE_1;

        // create new basket with feature
        Basket _basket = new Basket();
        vm.prank(PROXY);
        _basket.initialize( 
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        // Pre-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);

        // Execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(_basket), 1);
        vm.expectRevert("TNFT missing feature");
        _basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);

        // add feature to TNFT
        _addFeatureToCategory(address(realEstateTnft), 1, _asSingletonArrayUint(RE_FEATURE_1));

        // Execute a deposit
        vm.startPrank(JOE);
        _basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_mumbai_depositTNFT_feature_multiple() public {

        uint256[] memory featuresToAdd = new uint256[](3);
        featuresToAdd[0] = RE_FEATURE_2;
        featuresToAdd[1] = RE_FEATURE_3;
        featuresToAdd[2] = RE_FEATURE_4;

        string[] memory descriptionsToAdd = new string[](3);
        descriptionsToAdd[0] = "Desc for feat 2";
        descriptionsToAdd[1] = "Desc for feat 3";
        descriptionsToAdd[2] = "Desc for feat 4";
     
        // add more features to tnftType
        vm.startPrank(factoryOwner);
        ITNFTMetadataExt(address(metadata)).addFeatures(featuresToAdd, descriptionsToAdd);
        ITNFTMetadataExt(address(metadata)).addFeaturesForTNFTType(RE_TNFTTYPE, featuresToAdd);
        vm.stopPrank();

        // features to add to basket initially
        featuresToAdd = new uint256[](3);
        featuresToAdd[0] = RE_FEATURE_1;
        featuresToAdd[1] = RE_FEATURE_2;
        featuresToAdd[2] = RE_FEATURE_3;

        // create new basket with feature
        Basket _basket = new Basket();
        vm.prank(PROXY);
        _basket.initialize( 
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            featuresToAdd,
            address(this)
        );

        // Pre-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 2), false);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);
        assertEq(_basket.featureSupported(RE_FEATURE_2), true);
        assertEq(_basket.featureSupported(RE_FEATURE_3), true);

        // Try to execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(_basket), 1);
        vm.expectRevert("TNFT missing feature");
        _basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check 1.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), false);

        // add feature 1 to TNFT
        _addFeatureToCategory(address(realEstateTnft), 1, _asSingletonArrayUint(RE_FEATURE_1));

        // Try to execute a deposit
        vm.startPrank(JOE);
        vm.expectRevert("TNFT missing feature");
        _basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check 2.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), false);

        // add feature 2 to TNFT
        _addFeatureToCategory(address(realEstateTnft), 1, _asSingletonArrayUint(RE_FEATURE_2));

        // Try to execute a deposit
        vm.startPrank(JOE);
        vm.expectRevert("TNFT missing feature");
        _basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check 3.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), false);

        // add feature 3 to TNFT
        _addFeatureToCategory(address(realEstateTnft), 1, _asSingletonArrayUint(RE_FEATURE_3));

        // Try to execute a deposit
        vm.startPrank(JOE);
        _basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Post-state check 4.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 2), false);

        // add all featurs to TNFT 2
        _addFeatureToCategory(address(realEstateTnft), 2, _asSingletonArrayUint(RE_FEATURE_1));
        _addFeatureToCategory(address(realEstateTnft), 2, _asSingletonArrayUint(RE_FEATURE_2));
        _addFeatureToCategory(address(realEstateTnft), 2, _asSingletonArrayUint(RE_FEATURE_3));
        _addFeatureToCategory(address(realEstateTnft), 2, _asSingletonArrayUint(RE_FEATURE_4));
        assertEq(_basket.featureSupported(RE_FEATURE_4), false);

        // Try to execute a deposit
        vm.startPrank(NIK);
        realEstateTnft.approve(address(_basket), 2);
        _basket.depositTNFT(address(realEstateTnft), 2);
        vm.stopPrank();

        // Post-state check 5.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 2), true);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::batchDepositTNFT() is executed.
    function test_baskets_mumbai_batchDepositTNFT() public {

        uint256 preBal = realEstateTnft.balanceOf(JOE);
        uint256 amountTNFTs = 3;

        uint256[] memory tokenIds = _mintToken(address(realEstateTnft), amountTNFTs, RE_FINGERPRINT_1, JOE);
        address[] memory tnfts = new address[](amountTNFTs);
        for (uint256 i; i < tokenIds.length; ++i) {
            tnfts[i] = address(realEstateTnft);
        }

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), preBal + amountTNFTs);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), false);
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        // emit deposit logic 
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);
        uint256 sharePrice = basket.getSharePrice();

        // Execute a batch deposit
        vm.startPrank(JOE);
        for (uint256 i; i < amountTNFTs; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        uint256[] memory shares = basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", sharePrice);

        uint256 totalShares;
        for (uint i; i < amountTNFTs; ++i) {
            totalShares += shares[i];
        }

        // Post-state check
        assertEq(
            (basket.balanceOf(JOE) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBal);
        assertEq(realEstateTnft.balanceOf(address(basket)), amountTNFTs);

        assertEq(basket.balanceOf(JOE), usdValue * amountTNFTs);
        assertEq(basket.balanceOf(JOE), totalShares);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
        }

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, amountTNFTs);
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(deposited[i].tokenId, tokenIds[i]);
            assertEq(deposited[i].fingerprint, RE_FINGERPRINT_1);
        }

        // Try to call batchDepositNFT with diff size arrays -> revert
        tokenIds = new uint256[](1);
        tnfts = new address[](2);

        vm.expectRevert("Arrays not same size");
        basket.batchDepositTNFT(tnfts, tokenIds);
    }


    // ~ Redeem Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed.
    function test_baskets_mumbai_redeemTNFT_single() public {

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), 1);
        uint256 sharePrice = basket.getSharePrice();

        // Pre-state check
        assertEq(
            (basket.balanceOf(JOE) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], 1);

        // Joe performs a redeem
        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(JOE));
        vm.stopPrank();

        // Post-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed.
    function test_baskets_mumbai_redeemTNFT_single_rent_fromBalance() public {

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), 1);
        uint256 sharePrice = basket.getSharePrice();

        uint256 rentBal = 10_000 * USD;
        deal(address(MUMBAI_USDC), address(basket), rentBal);

        // Pre-state check
        assertEq(
            ((basket.balanceOf(JOE) * sharePrice) / 1 ether) + (rentBal * 10**12),
            basket.getTotalValueOfBasket()
        );

        assertEq(MUMBAI_USDC.balanceOf(address(basket)), rentBal);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        // Joe performs a redeem
        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(JOE));
        vm.stopPrank();

        // Post-state check
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertEq(MUMBAI_USDC.balanceOf(JOE), rentBal);

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed.
    function test_baskets_mumbai_redeemTNFT_single_rent_fromRentManager() public {

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // get nft value
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), 1);

        // deal category owner USDC to deposit into rentManager
        uint256 rentBal = 10_000 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, rentBal);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        MUMBAI_USDC.approve(address(rentManager), rentBal);
        rentManager.deposit(
            1,
            address(MUMBAI_USDC),
            rentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get rent value
        uint256 rentClaimable = rentManager.claimableRentForToken(1);
        assertEq(rentClaimable, 10_000 * USD); //1e6

        // Pre-state check
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), rentBal);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        // Joe performs a redeem
        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(JOE));
        vm.stopPrank();

        // Post-state check
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 0);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertEq(MUMBAI_USDC.balanceOf(JOE), rentBal);

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed for multiple TNFTs.
    function test_baskets_mumbai_redeemTNFT_multiple() public {

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), 2);
        basket.depositTNFT(address(realEstateTnft), 2);
        vm.stopPrank();

        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), 1);
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), 2);
        uint256 sharePrice = basket.getSharePrice();

        // Pre-state check
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

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, 2);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_2);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 2);
        assertEq(tokenIdLib[0], 1);
        assertEq(tokenIdLib[1], 2);

        // Joe performs a redeem
        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(JOE));
        vm.stopPrank();

        // Post-state check 1
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(NIK), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), usdValue2);
        assertEq(basket.totalSupply(), basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 2);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_2);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], 2);

        // Nik performs a redeem
        vm.startPrank(NIK);
        basket.redeemTNFT(address(realEstateTnft), 2, basket.balanceOf(NIK));
        vm.stopPrank();

        // Post-state check 2
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(NIK), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed for multiple TNFTs.
    ///         And allocates rent from claiming from rent manager of non-redeemed TNFTs.
    function test_baskets_mumbai_redeemTNFT_multiple_rent_fromRentManager() public {

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), 2);
        basket.depositTNFT(address(realEstateTnft), 2);
        vm.stopPrank();

        // get nft value
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), 1);
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), 2);

        // deal category owner USDC to deposit into rentManager
        uint256 rentBal1 = 20_000 * USD;
        uint256 rentBal2 = 2_000 * USD; // token2 is more valuable so give it less rent so method will have to claim from other TNFT rent.
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, rentBal1 + rentBal2);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for tnft 1
        MUMBAI_USDC.approve(address(rentManager), rentBal1);
        rentManager.deposit(
            1,
            address(MUMBAI_USDC),
            rentBal1,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for tnft 2
        MUMBAI_USDC.approve(address(rentManager), rentBal2);
        rentManager.deposit(
            2,
            address(MUMBAI_USDC),
            rentBal2,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // Pre-state check
        assertEq(rentManager.claimableRentForToken(1), rentBal1);
        assertEq(rentManager.claimableRentForToken(2), rentBal2);
        assertEq(basket.getRentBal(), (rentBal1 + rentBal2) * 10**12);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), rentBal1 + rentBal2);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);
        assertEq(MUMBAI_USDC.balanceOf(NIK), 0);

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(NIK), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 2);

        assertEq(basket.balanceOf(JOE), usdValue1);
        assertEq(basket.balanceOf(NIK), usdValue2);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, 2);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_2);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 2);
        assertEq(tokenIdLib[0], 1);
        assertEq(tokenIdLib[1], 2);

        // Nik performs a redeem of TNFT 2
        vm.startPrank(NIK);
        basket.redeemTNFT(address(realEstateTnft), 2, basket.balanceOf(NIK));
        vm.stopPrank();

        // Post-state check 1.
        assertEq(rentManager.claimableRentForToken(1), 0);
        assertEq(rentManager.claimableRentForToken(2), 0);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 0);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), (rentBal1 + rentBal2) - MUMBAI_USDC.balanceOf(NIK));
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);
        assertGt(MUMBAI_USDC.balanceOf(NIK), 0); // >0

        emit log_named_uint("USDC bal of Joe", MUMBAI_USDC.balanceOf(JOE));
        emit log_named_uint("USDC bal of Nik", MUMBAI_USDC.balanceOf(NIK));

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(NIK), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), usdValue1);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], 1);

        // Joe performs a redeem of TNFT 1
        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(JOE));
        vm.stopPrank();

        // Post-state check 2.
        assertEq(rentManager.claimableRentForToken(1), 0);
        assertEq(rentManager.claimableRentForToken(2), 0);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 0);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertGt(MUMBAI_USDC.balanceOf(JOE), 0); // >0
        assertGt(MUMBAI_USDC.balanceOf(NIK), 0); // >0

        emit log_named_uint("USDC bal of Joe", MUMBAI_USDC.balanceOf(JOE));
        emit log_named_uint("USDC bal of Nik", MUMBAI_USDC.balanceOf(NIK));

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(NIK), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 2), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    function test_baskets_mumbai_redeemTNFT_mathCheck1() public {
        // Mint Alice token worth $100
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000, // 100 GBP TODO: Switch to USD
            1,
            1,
            1,
            ALICE
        );
        uint256 aliceToken = tokenIds[0];

        // Mint Bob token worth $50
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            50_000, // 50 GBP TODO: Switch to USD
            1,
            1,
            2,
            BOB
        );
        uint256 bobToken = tokenIds[0];

        assertNotEq(aliceToken, bobToken);

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(ALICE), 1);
        assertEq(realEstateTnft.balanceOf(BOB), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(ALICE), 0);
        assertEq(basket.balanceOf(BOB), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        // Alice executes a deposit
        vm.startPrank(ALICE);
        realEstateTnft.approve(address(basket), aliceToken);
        basket.depositTNFT(address(realEstateTnft), aliceToken);
        vm.stopPrank();

        // Bob executes a deposit
        vm.startPrank(BOB);
        realEstateTnft.approve(address(basket), bobToken);
        basket.depositTNFT(address(realEstateTnft), bobToken);
        vm.stopPrank();

        // deal category owner USDC to deposit into rentManager
        uint256 aliceRentBal = 10 * USD;
        uint256 bobRentBal = 5 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, aliceRentBal + bobRentBal);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for alice's tnft
        MUMBAI_USDC.approve(address(rentManager), aliceRentBal);
        rentManager.deposit(
            aliceToken,
            address(MUMBAI_USDC),
            aliceRentBal,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for bob's tnft
        MUMBAI_USDC.approve(address(rentManager), bobRentBal);
        rentManager.deposit(
            bobToken,
            address(MUMBAI_USDC),
            bobRentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // skip to end of vesting

        // Sanity rent check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 5 * USD);
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 15 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        // TODO: Add check for share price

        // Bob executes a redeem of bobToken
        vm.startPrank(BOB);
        basket.redeemTNFT(address(realEstateTnft), bobToken, basket.balanceOf(BOB));
        vm.stopPrank();

        // Post-state check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 0);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 10 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 5 * USD);

        assertEq(realEstateTnft.balanceOf(ALICE), 0);
        assertEq(realEstateTnft.balanceOf(BOB), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(ALICE), (100 ether * 1.30 ether) / 1 ether); // Note: Odd exchange rate math
        assertEq(basket.balanceOf(BOB), 0);
        assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, aliceToken);
        assertEq(deposited[0].fingerprint, 1);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], aliceToken);
    }

    function test_baskets_mumbai_redeemTNFT_mathCheck2() public {
        // Mint Alice token worth $100
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000, // 100 GBP TODO: Switch to USD
            1,
            1,
            1,
            ALICE
        );
        uint256 aliceToken = tokenIds[0];

        // Mint Bob token worth $50
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            50_000, // 50 GBP TODO: Switch to USD
            1,
            1,
            2,
            BOB
        );
        uint256 bobToken = tokenIds[0];

        assertNotEq(aliceToken, bobToken);

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(ALICE), 1);
        assertEq(realEstateTnft.balanceOf(BOB), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(ALICE), 0);
        assertEq(basket.balanceOf(BOB), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        // Alice executes a deposit
        vm.startPrank(ALICE);
        realEstateTnft.approve(address(basket), aliceToken);
        basket.depositTNFT(address(realEstateTnft), aliceToken);
        vm.stopPrank();

        // Bob executes a deposit
        vm.startPrank(BOB);
        realEstateTnft.approve(address(basket), bobToken);
        basket.depositTNFT(address(realEstateTnft), bobToken);
        vm.stopPrank();

        // deal category owner USDC to deposit into rentManager
        uint256 aliceRentBal = 10 * USD;
        uint256 bobRentBal = 5 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, aliceRentBal + bobRentBal);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for alice's tnft
        MUMBAI_USDC.approve(address(rentManager), aliceRentBal);
        rentManager.deposit(
            aliceToken,
            address(MUMBAI_USDC),
            aliceRentBal,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for bob's tnft
        MUMBAI_USDC.approve(address(rentManager), bobRentBal);
        rentManager.deposit(
            bobToken,
            address(MUMBAI_USDC),
            bobRentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // skip to end of vesting

        // Sanity rent check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 5 * USD);
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 15 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        // TODO: Add check for share price

        // Alice executes a redeem of bobToken -> Only using half of her tokens
        vm.startPrank(ALICE);
        basket.redeemTNFT(address(realEstateTnft), bobToken, basket.balanceOf(ALICE) / 2);
        vm.stopPrank();

        // Post-state check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 0);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 10 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 5 * USD);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        assertEq(realEstateTnft.balanceOf(ALICE), 1);
        assertEq(realEstateTnft.balanceOf(BOB), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(ALICE), (50 ether * 1.30 ether) / 1 ether); // Note: Odd exchange rate math
        assertEq(basket.balanceOf(BOB), (50 ether * 1.30 ether) / 1 ether);
        assertEq(basket.totalSupply(), basket.balanceOf(ALICE) + basket.balanceOf(BOB));
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, aliceToken);
        assertEq(deposited[0].fingerprint, 1);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], aliceToken);
    }


    // ----------------------
    // View Method Unit Tests
    // ----------------------


    // ~ getTotalValueOfBasket ~

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket
    function test_baskets_mumbai_getTotalValueOfBasket_single() public {
        assertEq(basket.getTotalValueOfBasket(), 0);

        // deposit TNFT of certain value -> $650k usd
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // get nft value
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), 1);
        assertEq(usdValue1, 650_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager
        uint256 amount = 10_000 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        MUMBAI_USDC.approve(address(rentManager), amount);
        rentManager.deposit(
            1,
            address(MUMBAI_USDC),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get rent value
        uint256 rentClaimable = rentManager.claimableRentForToken(1);
        assertEq(rentClaimable, 10_000 * USD); //1e6

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), rentClaimable * 10**12);
        assertEq(totalValue, usdValue1 + basket.getRentBal());
    }

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket with many TNFTs.
    function test_baskets_mumbai_getTotalValueOfBasket_multiple() public {
        assertEq(basket.getTotalValueOfBasket(), 0);

        // Joe deposits TNFT of certain value -> $650k usd
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), 1);
        basket.depositTNFT(address(realEstateTnft), 1);
        vm.stopPrank();

        // Nik deposits TNFT of certain value -> $780k usd
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), 2);
        basket.depositTNFT(address(realEstateTnft), 2);
        vm.stopPrank();

        // get nft value of tnft 1
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), 1);
        assertEq(usdValue1, 650_000 ether); //1e18

        // get nft value of tnft 2
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), 2);
        assertEq(usdValue2, 780_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager for tnft 1 and tnft 2
        uint256 amount1 = 10_000 * USD;
        uint256 amount2 = 14_000 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, amount1 + amount2);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for tnft 1
        MUMBAI_USDC.approve(address(rentManager), amount1);
        rentManager.deposit(
            1,
            address(MUMBAI_USDC),
            amount1,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for tnft 2
        MUMBAI_USDC.approve(address(rentManager), amount2);
        rentManager.deposit(
            2,
            address(MUMBAI_USDC),
            amount2,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get claimable rent value for tnft 1
        uint256 rentClaimable1 = rentManager.claimableRentForToken(1);
        assertEq(rentClaimable1, amount1);

        // get claimable rent value for tnft 2
        uint256 rentClaimable2 = rentManager.claimableRentForToken(2);
        assertEq(rentClaimable2, amount2);

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), (rentClaimable1 * 10**12) + (rentClaimable2 * 10**12));
        assertEq(totalValue, usdValue1 + usdValue2 + basket.getRentBal());
    }

    // TODO: Write getTotalValueOfBasket test using fuzzing

    
}