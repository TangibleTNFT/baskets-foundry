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
import { BasketManager } from "../src/BasketsManager.sol";

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

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


// Mumbai RPC: https://rpc.ankr.com/polygon_mumbai

/**
 * @title BasketsManagerTest
 * @author Chase Brown
 * @notice This test file contains integration unit tests for the BasketManager contract. 
 */
contract BasketsManagerTest is Utility {

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

    // proxies
    TransparentUpgradeableProxy public basketManagerProxy;
    TransparentUpgradeableProxy public basketVrfConsumerProxy;
    ProxyAdmin public proxyAdmin;

    // ~ Actors ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4;

    uint256[] testArray1 = [8, 7, 4, 6, 9, 2, 10, 1, 3, 5];


    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).owner();
        proxyAdmin = new ProxyAdmin();

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
        factoryV2.mint(voucher1);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 1);
        factoryV2.mint(voucher2);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 2);
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
    function test_basketManager_deployBasket() public {

        // create features array
        uint256[] memory features = new uint256[](2);
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        // add features to initial deposit token
        _addFeatureToCategory(address(realEstateTnft), 1, features);

        // Pre-state check.
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), 1);
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(1)
        );
        vm.stopPrank();

        // Post-state check
        assertEq(basketShares.length, 1);

        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        assertEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE, basketManager.sort(features)))
        );
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
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), true);

        Basket.TokenData[] memory deposited = IBasket(_basket).getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);


        // create new features array with same features in different order
        features = new uint256[](2);
        features[0] = RE_FEATURE_1;
        features[1] = RE_FEATURE_2;

        // deploy another basket with same features
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), 2);
        vm.expectRevert("Basket already exists");
        basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(1)
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
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        // create features array
        uint256[] memory features = new uint256[](2);
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        // add features to initial deposit token
        _addFeatureToCategory(address(realEstateTnft), 1, features);
        _addFeatureToCategory(address(realEstateTnft), 2, features);

        // Pre-state check.
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), 1);
        realEstateTnft.approve(address(basketManager), 2);
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
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

        assertEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE, basketManager.sort(features)))
        );

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
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 1), true);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), 2), true);

        Basket.TokenData[] memory deposited = IBasket(_basket).getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, 2);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_2);
    }

    /// @notice Verifies proper state changes when a basket is deployed with no features
    function test_basketManager_deployBasket_noFeatures() public {

        // create features array
        uint256[] memory features = new uint256[](0);

        // Pre-state check.
        address[] memory basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 0);

        // deploy basket
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basketManager), 1);
        (IBasket _basket,) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(1)
        );
        vm.stopPrank();

        // Post-state check
        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        //assertEq(basketsArray[0], address(basket));  // global setup basket
        assertEq(basketsArray[0], address(_basket)); // local test basket

        assertEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE))
        );
        assertEq(
            basketManager.hashedFeaturesForBasket(address(_basket)),
            keccak256(abi.encodePacked(RE_TNFTTYPE, features))
        );

        emit log_named_bytes32("Features hash", basketManager.hashedFeaturesForBasket(address(_basket)));
    }


    // ~ sort testing ~

    /// @notice This verifies correct logic with the sort method inside BasketsDeployer contract
    function test_basketManager_insertionSort() public {

        // Sort testArray1 of size 10.
        uint256[] memory sortedArray = basketManager.sort(testArray1);

        // Verify elements were sorted correctly.
        for (uint256 i; i < sortedArray.length; ++i) {
            assertEq(sortedArray[i], i + 1);
            emit log_uint(sortedArray[i]);
        }

        // Create features array of size 0.
        uint256[] memory featuresArray4 = new uint256[](0);

        // Sort
        sortedArray = basketManager.sort(featuresArray4);
        assertEq(sortedArray.length, 0);

        // Create features array of size 1.
        uint256[] memory featuresArray1 = new uint256[](1);
        featuresArray1[0] = RE_FEATURE_3;

        // Sort
        sortedArray = basketManager.sort(featuresArray1);

        // Verify
        assertEq(sortedArray[0], RE_FEATURE_3);

        // Create features array of size 2.
        uint256[] memory featuresArray2 = new uint256[](2);
        featuresArray2[0] = RE_FEATURE_4;
        featuresArray2[1] = RE_FEATURE_2;

        // Sort
        sortedArray = basketManager.sort(featuresArray2);

        // Verify
        assertEq(sortedArray[0], RE_FEATURE_2);
        assertEq(sortedArray[1], RE_FEATURE_4);

        // Create features array of size 4.
        uint256[] memory featuresArray3 = new uint256[](4);
        featuresArray3[0] = RE_FEATURE_4;
        featuresArray3[1] = RE_FEATURE_2;
        featuresArray3[2] = RE_FEATURE_3;
        featuresArray3[3] = RE_FEATURE_1;

        // Sort
        sortedArray = basketManager.sort(featuresArray3);

        // Verify
        assertEq(sortedArray[0], RE_FEATURE_1);
        assertEq(sortedArray[1], RE_FEATURE_2);
        assertEq(sortedArray[2], RE_FEATURE_3);
        assertEq(sortedArray[3], RE_FEATURE_4);
    }


    // ~ encodePacked testing ~

    /// @notice This test verifies the use of abi.encodePacked.
    function test_basketManager_encodePacked() public {
        uint256 tnftType = 2;

        // hash state array of randomized variables of size 10.
        bytes32 hashedCombo = keccak256(abi.encodePacked(tnftType, testArray1));
        emit log_bytes32(hashedCombo);

        // create local array to imitate state array.
        uint256[] memory testArrayLocal = new uint256[](10);
        testArrayLocal[0] = 8;
        testArrayLocal[1] = 7;
        testArrayLocal[2] = 4;
        testArrayLocal[3] = 6;
        testArrayLocal[4] = 9;
        testArrayLocal[5] = 2;
        testArrayLocal[6] = 10;
        testArrayLocal[7] = 1;
        testArrayLocal[8] = 3;
        testArrayLocal[9] = 5;

        // hash local array
        bytes32 hashedCombo1 = keccak256(abi.encodePacked(tnftType, testArrayLocal));
        emit log_bytes32(hashedCombo1);

        // verify hashed local array and hashed state array have the same hash value.
        assertEq(hashedCombo, hashedCombo1);

        // flip elements
        testArrayLocal[0] = 3;
        testArrayLocal[1] = 1;
        testArrayLocal[2] = 10;
        testArrayLocal[3] = 5;
        testArrayLocal[4] = 7;
        testArrayLocal[5] = 4;
        testArrayLocal[6] = 2;
        testArrayLocal[7] = 9;
        testArrayLocal[8] = 8;
        testArrayLocal[9] = 6;

        // verify hashed local array and hashed state array have the same hash value when sorted.
        assertEq(
            keccak256(abi.encodePacked(tnftType, basketManager.sort(testArrayLocal))),
            keccak256(abi.encodePacked(tnftType, basketManager.sort(testArray1)))
        );

        bytes32 hashedCombo2 = keccak256(abi.encodePacked(tnftType));
        emit log_bytes32(hashedCombo2);

        uint256[] memory emptyArray = new uint256[](0);
        bytes32 hashedCombo3 = keccak256(abi.encodePacked(tnftType, emptyArray));
        emit log_bytes32(hashedCombo3);

        assertEq(hashedCombo2, hashedCombo3);
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