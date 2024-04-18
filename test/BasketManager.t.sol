// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { CurrencyCalculator } from "../src/CurrencyCalculator.sol";
import { BasketManager } from "../src/BasketManager.sol";
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";
import { ArrayUtils } from "../src/libraries/ArrayUtils.sol";

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

/**
 * @title BasketsManagerTest
 * @author Chase Brown
 * @notice This test file contains integration unit tests for the BasketManager contract. 
 */
contract BasketManagerTest is Utility {
    using ArrayUtils for uint256[];

    Basket public basket;
    BasketManager public basketManager;
    CurrencyCalculator public currencyCalculator;

    //contracts
    IFactory public factoryV2 = IFactory(Unreal_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Unreal_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Unreal_RealtyOracleTangibleV2);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Unreal_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Unreal_Marketplace);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Unreal_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Unreal_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Unreal_TNFTMetadata);
    RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Unreal_RWAPriceNotificationDispatcher);

    // proxies
    ERC1967Proxy public basketManagerProxy;
    ERC1967Proxy public basketVrfConsumerProxy;

    // ~ Actors ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public TANGIBLE_LABS;

    uint256[] internal mintedToken;

    uint256 internal JOE_TOKEN_1;
    uint256 internal JOE_TOKEN_2;


    function setUp() public {

        vm.createSelectFork(UNREAL_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).owner();

        // new category owner
        TANGIBLE_LABS = factoryV2.categoryOwner(ITangibleNFT(realEstateTnft));

        // Deploy basket implementation
        basket = new Basket();

        // Deploy CurrencyCalculator -> not upgradeable
        currencyCalculator = new CurrencyCalculator(address(factoryV2));

        // Deploy basketManager
        basketManager = new BasketManager();

        // Deploy proxy for basketManager -> initialize
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(UNREAL_DAI),
                false,
                address(currencyCalculator)
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
        // IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
        //     RE_FINGERPRINT_1,  // fingerprint
        //     500_000_000,     // weSellAt
        //     0,            // lockedAmount
        //     10,           // stock
        //     uint16(826),  // currency -> GBP ISO NUMERIC CODE
        //     uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        // );
        // IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
        //     RE_FINGERPRINT_2,  // fingerprint
        //     600_000_000,     // weSellAt
        //     0,            // lockedAmount
        //     10,           // stock
        //     uint16(826),  // currency -> GBP ISO NUMERIC CODE
        //     uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        // );
        IPriceOracleExt(address(chainlinkRWAOracle)).updateItem( // 1
            RE_FINGERPRINT_1,
            500_000_000,
            0
        );
        IPriceOracleExt(address(chainlinkRWAOracle)).updateStock(
            RE_FINGERPRINT_1,
            10
        );
        IPriceOracleExt(address(chainlinkRWAOracle)).updateItem( // 2
            RE_FINGERPRINT_2,
            600_000_000,
            0
        );
        IPriceOracleExt(address(chainlinkRWAOracle)).updateStock(
            RE_FINGERPRINT_2,
            10
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
        assertEq(basketManager.isBasket(address(0)), false);
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ Initializer ~

    /// @notice Verifies proper state changes when BasketManager::initialize is executed
    function test_basketManager_initialize() public {
        BasketManager newBasketManager = new BasketManager();

        ERC1967Proxy newBasketManagerProxy = new ERC1967Proxy(
            address(newBasketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(UNREAL_DAI),
                false,
                address(currencyCalculator)
            )
        );
        newBasketManager = BasketManager(address(newBasketManagerProxy));

        assertEq(address(newBasketManager.currencyCalculator()), address(currencyCalculator));
        assertEq(newBasketManager.primaryRentToken(), address(UNREAL_DAI));
        assertEq(newBasketManager.rentIsRebaseToken(), false);
        assertEq(newBasketManager.featureLimit(), 10);
    }

    /// @notice Verifies initial state initializer restrictions for BasketManager::initialize
    function test_basketManager_initialize_restrictions() public {
        BasketManager newBasketManager = new BasketManager();

        // basketImplementation cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        ERC1967Proxy newBasketManagerProxy = new ERC1967Proxy(
            address(newBasketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(0),
                address(factoryV2),
                address(UNREAL_DAI),
                false,
                address(currencyCalculator)
            )
        );

        // factory cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        newBasketManagerProxy = new ERC1967Proxy(
            address(newBasketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(0),
                address(UNREAL_DAI),
                false,
                address(currencyCalculator)
            )
        );

        // rent token cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        newBasketManagerProxy = new ERC1967Proxy(
            address(newBasketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(0),
                false,
                address(currencyCalculator)
            )
        );

        // currency calculator cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        newBasketManagerProxy = new ERC1967Proxy(
            address(newBasketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(UNREAL_DAI),
                false,
                address(0)
            )
        );
    }


    // ~ deployBasket testing ~

    /// @notice Verifies proper state changes when a basket is deployed with features
    function test_basketManager_deployBasket_single() public {

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
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            UK_ISO,
            features.sort(),
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        // Post-state check
        assertEq(basketShares.length, 1);
        assertEq(_basket.basketManager(), address(basketManager));

        uint256[] memory supportedFeatures = _basket.getSupportedFeatures();
        assertEq(supportedFeatures.length, features.length);
        assertEq(supportedFeatures[0], features[0]);
        assertEq(supportedFeatures[1], features[1]);

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        (bytes32 basketHash,,,) = basketManager.getBasketInfo(address(_basket));

        assertNotEq(
            basketHash,
            keccak256(abi.encodePacked(RE_TNFTTYPE, features))
        );

        assertEq(basketManager.isBasket(address(_basket)), true);

        uint256 sharePrice = IBasket(_basket).getSharePrice();

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(_basket)), 1);

        assertWithinDiff(
            (_basket.balanceOf(JOE) * sharePrice) / 1 ether,
            _basket.getTotalValueOfBasket(),
            100000
        );

        assertEq(
            basketManager.fetchBasketByHash(basketHash),
            address(_basket)
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

    /// @notice Verifies proper restrictions when a basket is deployed with features
    function test_basketManager_deployBasket_restrictions() public {

        // create features array
        uint256[] memory features = new uint256[](2);
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        address[] memory emptyAddrArr = new address[](0);
        uint256[] memory emptyUintArr = new uint256[](0);

        // add features to initial deposit token
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_1, features);
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_2, features);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_1);
        basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            UK_ISO,
            features.sort(),
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        // ensure elements arent sorted
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        // deploy same basket without sorting -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.FeaturesNotSorted.selector));
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // ensure duplicates
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_2;

        // deploy same basket with duplicates -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.FeaturesNotSorted.selector));
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // create new features array with same features in different order
        features[0] = RE_FEATURE_1;
        features[1] = RE_FEATURE_2;

        // deploy another basket with same name -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.NameNotAvailable.selector, "Tangible Basket Token"));
        basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // deploy another basket with same symbol -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.SymbolNotAvailable.selector, "TBT"));
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT",
            RE_TNFTTYPE,
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // deploy another basket with same features -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.BasketAlreadyExists.selector));
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_2)
        );
        vm.stopPrank();

        // deploy another basket with diff array sizes -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.InvalidArrayEntry.selector));
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            emptyUintArr
        );
        vm.stopPrank();

        // deploy another basket with no deposit -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.InvalidArrayEntry.selector));
        basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features,
            emptyAddrArr,
            emptyUintArr
        );
        vm.stopPrank();

        uint256 unSupportedType = 999999999999999;

        // deploy another basket with same features -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.InvalidTnftType.selector, unSupportedType));
        basketManager.deployBasket(
            "Tangible Basket Token 1",
            "TBT1",
            unSupportedType,
            UK_ISO,
            features.sort(),
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        vm.prank(factoryOwner);
        basketManager.setFeatureLimit(1);

        // deploy another basket with same features -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.FeatureLimitExceeded.selector));
        basketManager.deployBasket(
            "Tangible Basket Token 1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features.sort(),
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();

        vm.prank(factoryOwner);
        basketManager.setFeatureLimit(10);

        features[0] = 999999999999998;
        features[1] = 999999999999999;

        // deploy another basket with different features, but not supported under type -> revert
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), JOE_TOKEN_2);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.FeatureNotSupportedInType.selector, RE_TNFTTYPE, features[0]));
        basketManager.deployBasket(
            "Tangible Basket Token 1",
            "TBT1",
            RE_TNFTTYPE,
            UK_ISO,
            features.sort(),
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(JOE_TOKEN_1)
        );
        vm.stopPrank();
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
            UK_ISO,
            features.sort(),
            tnfts,
            tokenIds
        );
        vm.stopPrank();

        // Post-state check
        assertEq(basketShares.length, 2);
        assertEq(_basket.basketManager(), address(basketManager));

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        assertEq(basketManager.isBasket(address(_basket)), true);

        uint256 sharePrice = IBasket(_basket).getSharePrice();

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(_basket)), 2);

        assertWithinDiff(
            (_basket.balanceOf(JOE) * sharePrice) / 1 ether,
            _basket.getTotalValueOfBasket(),
            100000
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
        assertEq(_basket.basketManager(), address(basketManager));

        (bytes32 basketHash,,,) = basketManager.getBasketInfo(address(_basket));

        assertEq(basketHash, keccak256(abi.encodePacked(RE_TNFTTYPE, location)));
        assertEq(basketHash, keccak256(abi.encodePacked(RE_TNFTTYPE, location, features)));

        emit log_named_bytes32("Features hash", basketHash);
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
        vm.expectRevert();
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
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

        assertWithinDiff(
            (_basket.balanceOf(JOE) * sharePrice) / 1 ether,
            _basket.getTotalValueOfBasket(),
            100000
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

        ERC20Mock MOCK_DAI = new ERC20Mock();

        uint256 amount = 1_000 * WAD;
        deal(address(MOCK_DAI), address(basketManager), amount);

        // ~ Pre-state check ~

        assertEq(MOCK_DAI.balanceOf(address(basketManager)), amount);
        assertEq(MOCK_DAI.balanceOf(address(factoryOwner)), 0);

        // ~ Execute withdrawERC20 ~

        // force revert -> address(0)
        vm.prank(factoryOwner);
        vm.expectRevert(BasketManager.ZeroAddress.selector);
        basketManager.withdrawERC20(address(0));

        // withdraw DAI balance -> success
        vm.prank(factoryOwner);
        basketManager.withdrawERC20(address(MOCK_DAI));

        // ~ Post-state check ~

        assertEq(MOCK_DAI.balanceOf(address(basketManager)), 0);
        assertEq(MOCK_DAI.balanceOf(address(factoryOwner)), amount);

        // force revert -> Insufficient amount
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.InsufficientBalance.selector));
        basketManager.withdrawERC20(address(MOCK_DAI));
    }


    // ~ setters ~

    /// @notice Verifies correct state changes when BasketManager::setBasketsVrfConsumer is executed.
    function test_basketManager_setBasketsVrfConsumer() public {
        // Pre-state check.
        assertEq(basketManager.basketsVrfConsumer(), address(0));

        // Execute setBasketsVrfConsumer with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
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

        // Execute setFeatureLimit
        vm.prank(factoryOwner);
        basketManager.setFeatureLimit(100);

        // Post-state check.
        assertEq(basketManager.featureLimit(), 100);
    }

    /// @notice Verifies restrictions when BasketManager::setFeatureLimit is executed.
    function test_basketManager_setFeatureLimit_restrictions() public {
        // bob cannot call setFeatureLimit
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketManager.setFeatureLimit(100);
    }

    /// @notice Verifies correct state changes when BasketManager::setCurrencyCalculator is executed.
    function test_basketManager_setCurrencyCalculator() public {
        // Pre-state check.
        assertNotEq(address(basketManager.currencyCalculator()), address(222));

        // Execute setCurrencyCalculator
        vm.prank(factoryOwner);
        basketManager.setCurrencyCalculator(address(222));

        // Post-state check.
        assertEq(address(basketManager.currencyCalculator()), address(222));

    }

    /// @notice Verifies restrictions when BasketManager::setCurrencyCalculator is executed.
    function test_basketManager_setCurrencyCalculator_restrictions() public {
        // Execute setCurrencyCalculator with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        basketManager.setCurrencyCalculator(address(0));

        // bob cannot call setCurrencyCalculator
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketManager.setCurrencyCalculator(address(222));
    }

    /// @notice Verifies correct state changes when BasketManager::setRevenueDistributor is executed.
    function test_basketManager_setRevenueDistributor() public {
        // Pre-state check.
        assertNotEq(address(basketManager.revenueDistributor()), address(222));

        // Execute setRevenueDistributor
        vm.prank(factoryOwner);
        basketManager.setRevenueDistributor(address(222));

        // Post-state check.
        assertEq(address(basketManager.revenueDistributor()), address(222));

    }

    /// @notice Verifies restrictions when BasketManager::setRevenueDistributor is executed.
    function test_basketManager_setRevenueDistributor_restrictions() public {
        // Execute setRevenueDistributor with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        basketManager.setRevenueDistributor(address(0));

        // bob cannot call setRevenueDistributor
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketManager.setRevenueDistributor(address(222));
    }

    /// @notice Verifies correct state changes when BasketManager::updateBasketImplementation is executed.
    function test_basketManager_updateBasketImplementation() public {
        Basket newBasket = new Basket();

        // Pre-state check.
        assertNotEq(basketManager.beacon().implementation(), address(newBasket));

        // Execute updateBasketImplementation
        vm.prank(factoryOwner);
        basketManager.updateBasketImplementation(address(newBasket));

        // Post-state check.
        assertEq(basketManager.beacon().implementation(), address(newBasket));

    }

    /// @notice Verifies restrictions when BasketManager::updateBasketImplementation is executed.
    function test_basketManager_updateBasketImplementation_restrictions() public {
        Basket newBasket = new Basket();

        // Execute updateBasketImplementation with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        basketManager.updateBasketImplementation(address(0));

        // bob cannot call updateBasketImplementation
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketManager.updateBasketImplementation(address(newBasket));
    }

    /// @notice Verifies correct state changes when BasketManager::setRebaseController is executed.
    function test_basketManager_setRebaseController() public {
        // Pre-state check.
        assertNotEq(address(basketManager.rebaseController()), address(222));

        // Execute setRebaseController
        vm.prank(factoryOwner);
        basketManager.setRebaseController(address(222));

        // Post-state check.
        assertEq(address(basketManager.rebaseController()), address(222));

    }

    /// @notice Verifies restrictions when BasketManager::setRebaseController is executed.
    function test_basketManager_setRebaseController_restrictions() public {
        // Execute setRebaseController with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        basketManager.setRebaseController(address(0));

        // bob cannot call setRebaseController
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketManager.setRebaseController(address(222));
    }

    /// @notice Verifies correct state changes when BasketManager::updatePrimaryRentToken is executed.
    function test_basketManager_updatePrimaryRentToken() public {
        // Pre-state check.
        assertEq(basketManager.primaryRentToken(), address(UNREAL_DAI));
        assertEq(basketManager.rentIsRebaseToken(), false);

        // Execute updatePrimaryRentToken
        vm.prank(factoryOwner);
        basketManager.updatePrimaryRentToken(address(222), true);

        // Post-state check.
        assertEq(basketManager.primaryRentToken(), address(222));
        assertEq(basketManager.rentIsRebaseToken(), true);
    }

    /// @notice Verifies restrictions when BasketManager::updatePrimaryRentToken is executed.
    function test_basketManager_updatePrimaryRentToken_restrictions() public {
        // Execute updatePrimaryRentToken with address(0) -> revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.ZeroAddress.selector));
        basketManager.updatePrimaryRentToken(address(0), false);

        // bob cannot call updatePrimaryRentToken
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketManager.updatePrimaryRentToken(address(222), false);
    }
}