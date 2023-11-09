// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";

import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

// tangible interface imports
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";
import { IMarketplace } from "@tangible/interfaces/IMarketplace.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


// Mumbai RPC: https://rpc.ankr.com/polygon_mumbai

/**
 * @title BasketsManagerTest
 * @author Chase Brown
 * @notice This test file contains integration unit tests for the BasketManager contract. 
 */
contract BasketManagerTest is Utility {

    Basket public basket;
    BasketManager public basketManager;

    //contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Mumbai_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Mumbai_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);
    RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Mumbai_RWAPriceNotificationDispatcher);

    // proxies
    TransparentUpgradeableProxy public basketManagerProxy;
    TransparentUpgradeableProxy public basketVrfConsumerProxy;
    ProxyAdmin public proxyAdmin;

    // ~ Actors ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4;

    uint256[] testArray1 = [8, 7, 4, 6, 9, 2, 10, 1, 3, 5];

    uint256[] internal mintedToken;

    uint256 internal JOE_TOKEN_1;
    uint256 internal JOE_TOKEN_2;


    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).owner();
        proxyAdmin = new ProxyAdmin(address(this));

        basket = new Basket();

        // Deploy basketManager
        basketManager = new BasketManager();

        // Deploy proxy for basketManager -> initialize
        basketManagerProxy = new TransparentUpgradeableProxy(
            address(basketManager),
            address(proxyAdmin),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2)
            )
        );
        basketManager = BasketManager(address(basketManagerProxy));

        // whitelist basketManager on notificationDispatcher
        vm.prank(TANGIBLE_LABS); // category owner
        notificationDispatcher.addWhitelister(address(basketManager));

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

        // set basketManager
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // set currencyFeed
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        // configure features to add to metadata contract
        uint256[] memory featuresArr = new uint256[](4);
        featuresArr[0] = RE_FEATURE_1;
        featuresArr[1] = RE_FEATURE_2;
        featuresArr[2] = RE_FEATURE_3;
        featuresArr[3] = RE_FEATURE_4;

        string[] memory descriptionsArr = new string[](4);
        descriptionsArr[0] = "Feature 1";
        descriptionsArr[1] = "Feature 2";
        descriptionsArr[2] = "Feature 3";
        descriptionsArr[3] = "Feature 4";

        vm.startPrank(factoryOwner);
        // add feature to metadata contract
        ITNFTMetadataExt(address(metadata)).addFeatures(
            featuresArr,
            descriptionsArr
        );
        // add feature to TNFTtype in metadata contract
        ITNFTMetadataExt(address(metadata)).addFeaturesForTNFTType(
            RE_TNFTTYPE,
            featuresArr
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

        // Tangible Labs mints token and sends it to Joe
        vm.startPrank(TANGIBLE_LABS);

        mintedToken = factoryV2.mint(voucher1);
        JOE_TOKEN_1 = mintedToken[0];
        assertEq(realEstateTnft.ownerOf(JOE_TOKEN_1), TANGIBLE_LABS);

        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, JOE_TOKEN_1);

        mintedToken = factoryV2.mint(voucher2);
        JOE_TOKEN_2 = mintedToken[0];
        assertEq(realEstateTnft.ownerOf(JOE_TOKEN_2), TANGIBLE_LABS);

        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, JOE_TOKEN_2);

        vm.stopPrank();

        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // labels
        vm.label(address(factoryV2), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(chainlinkRWAOracle), "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(JOE, "JOE");
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


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_basketManager_init_state() public {
        assertEq(basketManager.featureLimit(), 10);
        assertEq(basketManager.beacon().implementation(), address(basket));
        assertEq(basketManager.factory(), address(factoryV2));
    }


    // ----------
    // Unit Tests
    // ----------


    // ~ deployBasket testing ~

    /// @notice Verifies proper state changes when a basket is deployed with features
    function test_basketManager_deployBasket_single() public {

        // create features array
        uint256[] memory features = new uint256[](2);
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        address[] memory emptyAddrArr = new address[](0);
        uint256[] memory emptyUintArr = new uint256[](0);

        // add features to initial deposit token
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_1, features);
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_2, features);

        // Pre-state check.
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_1);
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        // Post-state check
        assertEq(basketShares.length, 1);

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        assertNotEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE, features))
        );

        assertEq(basketManager.isBasket(address(_basket)), true);

        uint256 sharePrice = IBasket(_basket).getSharePrice();

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(_basket)), 1);

        assertEq(
            (_basket.balanceOf(JOE) * sharePrice) / 1 ether,
            _basket.getTotalValueOfBasket()
        );

        assertEq(_basket.balanceOf(JOE), basketShares[0]);
        assertEq(_basket.totalSupply(), _basket.balanceOf(JOE));
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_1), true);

        Basket.TokenData[] memory deposited = IBasket(_basket).getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);


        // create new features array with same features in different order
        features = new uint256[](2);
        features[0] = RE_FEATURE_1;
        features[1] = RE_FEATURE_2;

        // deploy another basket with same name -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert("Name not available");
        basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // deploy another basket with same symbol -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert("Symbol not available");
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // deploy another basket with same features -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert("Basket already exists");
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // deploy another basket with no deposit -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert("Must be an initial deposit");
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            UK_ISO,
            features,
            emptyAddrArr,
            emptyUintArr
        );
        vm.stopPrank();

        // deploy another basket with same features -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            UK_ISO,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 2);
    }

    /// @notice Verifies proper state changes when a basket is deployed with features
    function test_basketManager_deployBasket_multipleInitial() public {

        // create tokenId array for initial deposit
        address[] memory tnfts = new address[](2);
        tnfts[0] = address(realEstateTnft);
        tnfts[1] = address(realEstateTnft);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = JOE_TOKEN_1;
        tokenIds[1] = JOE_TOKEN_2;

        // create features array
        uint256[] memory features = new uint256[](2);
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        // add features to initial deposit token
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_1, features);
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_2, features);

        // Pre-state check.
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_1);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            tnfts,
            tokenIds
        );
        vm.stopPrank();

        // Post-state check
        assertEq(basketShares.length, 2);

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        // assertEq(
        //     basketManager.hashedFeaturesForBasket(address(_basket)),
        //     keccak256(abi.encodePacked(RE_TNFTTYPE, basketManager.sort(features)))
        // );

        assertEq(basketManager.isBasket(address(_basket)), true);

        uint256 sharePrice = IBasket(_basket).getSharePrice();

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(_basket)), 2);

        assertEq(
            (_basket.balanceOf(JOE) * sharePrice) / 1 ether,
            _basket.getTotalValueOfBasket()
        );

        assertEq(_basket.balanceOf(JOE), basketShares[0] + basketShares[1]);
        assertEq(_basket.totalSupply(), _basket.balanceOf(JOE));
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_1), true);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_2), true);

        Basket.TokenData[] memory deposited = IBasket(_basket).getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, JOE_TOKEN_2);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_2);
    }

    /// @notice Verifies proper state changes when a basket is deployed with no features
    function test_basketManager_deployBasket_noFeatures() public {

        // create features array
        uint256[] memory features = new uint256[](0);

        uint16 location = 0;

        // Pre-state check.
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_1);
        (IBasket _basket,) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            location,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        // Post-state check
        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket)); // local test basket

        assertEq(_basket.location(), location);

        assertEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE, location))
        );
        assertEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE, location, features))
        );

        emit log_named_bytes32("Features hash", basketManager.hashedFeaturesForBasket(address(_basket)));
    }

    /// @notice Verifies proper state changes when a basket is deployed with a specific location
    function test_basketManager_deployBasket_location() public {

        // ~ Config ~

        // create features array
        uint256[] memory features = new uint256[](0);

        // ~ Pre-state check ~

        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // deploy basket -> revert -> deposit tokens dont support US ISO Code.
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_1);
        vm.expectRevert("Token incompatible");
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            US_ISO, // US ISO code
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );

        // deploy basket -> success
        (_basket, basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            UK_ISO, // UK ISO code
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        // ~ Post-state check ~

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        assertEq(basketManager.isBasket(address(_basket)), true);

        assertEq(_basket.location(), UK_ISO);

        uint256 sharePrice = IBasket(_basket).getSharePrice();

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(_basket)), 1);

        assertEq(
            (_basket.balanceOf(JOE) * sharePrice) / 1 ether,
            _basket.getTotalValueOfBasket()
        );

        assertEq(_basket.balanceOf(JOE), basketShares[0]);
        assertEq(_basket.totalSupply(), _basket.balanceOf(JOE));
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_1), true);

        Basket.TokenData[] memory deposited = IBasket(_basket).getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
    }


    // ~ withdrawERC20 ~

    /// @notice Verifies proper state changes when BasketManager::withdrawERC20 is executed.
    function test_basketManager_withdrawERC20() public {
        
        // ~ Config ~

        uint256 amount = 1_000 * USD;
        deal(address(MUMBAI_USDC), address(basketManager), amount);

        // ~ Pre-state check ~

        assertEq(MUMBAI_USDC.balanceOf(address(basketManager)), amount);
        assertEq(MUMBAI_USDC.balanceOf(address(factoryOwner)), 0);

        // ~ Execute withdrawERC20 ~

        // force revert -> address(0)
        vm.prank(factoryOwner);
        vm.expectRevert("Address cannot be zero address");
        basketManager.withdrawERC20(address(0));

        // withdraw USDC balance -> success
        vm.prank(factoryOwner);
        basketManager.withdrawERC20(address(MUMBAI_USDC));

        // ~ Post-state check ~

        assertEq(MUMBAI_USDC.balanceOf(address(basketManager)), 0);
        assertEq(MUMBAI_USDC.balanceOf(address(factoryOwner)), amount);

        // force revert -> Insufficient amount
        vm.prank(factoryOwner);
        vm.expectRevert("Insufficient token balance");
        basketManager.withdrawERC20(address(MUMBAI_USDC));
    }

    
    // ~ destroyBasket ~

    /// @notice Verifies proper state changes when BasketManager::destroyBasket is executed.
    function test_basketManager_destroyBasket() public {

        // ~ Config ~

        uint256[] memory features = new uint256[](0);
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        // deploy basket to eventually destroy
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_1);
        (IBasket _basket, ) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        bytes32 _hash = basketManager.hashedFeaturesForBasket(address(_basket));
        assertEq(basketManager.hashedFeaturesForBasket(address(_basket)), _hash);

        // ~ Pre-state check ~

        assertEq(basketManager.checkBasketAvailability(_hash), false);

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        assertEq(basketManager.isBasket(address(_basket)), true);

        assertNotEq(basketManager.basketNames(address(_basket)), "");
        assertNotEq(basketManager.basketSymbols(address(_basket)), "");

        assertEq(basketManager.nameHashTaken(basketManager.basketNames(address(_basket))), true);
        assertEq(basketManager.symbolHashTaken(basketManager.basketSymbols(address(_basket))), true);

        // ~ Execute destroyBasket() ~

        vm.prank(factoryOwner);
        basketManager.destroyBasket(address(_basket));

        // ~ Post-state check ~

        assertEq(basketManager.checkBasketAvailability(_hash), true);

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        assertEq(basketManager.isBasket(address(_basket)), false);

        assertEq(basketManager.hashedFeaturesForBasket(address(_basket)), "");
        assertEq(basketManager.basketNames(address(_basket)), "");
        assertEq(basketManager.basketSymbols(address(_basket)), "");

        assertEq(basketManager.nameHashTaken(basketManager.basketNames(address(_basket))), false);
        assertEq(basketManager.symbolHashTaken(basketManager.basketSymbols(address(_basket))), false);
    }


    // ~ setters ~

    /// @notice Verifies correct state changes when BasketManager::setBasketsVrfConsumer is executed.
    function test_basketManager_setBasketsVrfConsumer() public {
        // Pre-state check.
        assertEq(basketManager.basketsVrfConsumer(), address(0));

        // Execute setBasketsVrfConsumer with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert("_basketsVrfConsumer == address(0)");
        basketManager.setBasketsVrfConsumer(address(0));

        // Execute setBasketsVrfConsumer -> success
        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(222));

        // Post-state check.
        assertEq(basketManager.basketsVrfConsumer(), address(222));
    }

    /// @notice Verifies correct state changes when BasketManager::setFeatureLimit is executed.
    function test_basketManager_setFeatureLimit() public {
        // Pre-state check.
        assertEq(basketManager.featureLimit(), 10);

        // Execute setFeatureLimit with same value -> revert
        vm.prank(factoryOwner);
        vm.expectRevert("Already set");
        basketManager.setFeatureLimit(10);

        // Execute setFeatureLimit -> success
        vm.prank(factoryOwner);
        basketManager.setFeatureLimit(100);

        // Post-state check.
        assertEq(basketManager.featureLimit(), 100);
    }

}