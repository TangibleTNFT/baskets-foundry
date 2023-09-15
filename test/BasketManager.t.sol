// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// local contracts
import { Basket } from "../src/Baskets.sol";
import { IBasket } from "../src/interfaces/IBaskets.sol";
import { BasketManager } from "../src/BasketsManager.sol";

import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

// tangible contract imports
import { FactoryProvider } from "@tangible/FactoryProvider.sol";

// tangible interface imports
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
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

contract BasketsManagerTest is Test, Utility {

    Basket public basket;
    BasketManager public basketManager;

    //contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    IFactoryProvider public factoryProvider = IFactoryProvider(Mumbai_FactoryProvider);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Mumbai_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Mumbai_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);

    // ~ Actors ~

    address public factoryOwner = IOwnable(address(factoryV2)).contractOwner();
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4;

    uint256[] testArray1 = [8, 7, 4, 6, 9, 2, 10, 1, 3, 5];


    event log_named_bool(string key, bool val);

    function setUp() public {

        //uint256[] memory features = new uint256[](0);
        basket = new Basket();

        // Deploy BasketManager
        basketManager = new BasketManager(address(basket), address(factoryProvider));

        // basket = new Basket(
        //     "Tangible Basket Token",
        //     "TBT",
        //     address(factoryProvider),
        //     RE_TNFTTYPE,
        //     address(currencyFeed),
        //     MUMBAI_USDC,
        //     features,
        //     address(this)
        // );

        // add basket to basketManager
        // vm.prank(factoryOwner);
        // basketManager.addBasket(address(basket));

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
        vm.label(address(factoryProvider), "FACTORY_PROVIDER");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(JOE, "JOE");
        vm.label(NIK, "NIK");
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
    function _addFeatureToCategory(address _tnft, uint256 _tokenId, uint256[] memory _features) public {
        vm.prank(TANGIBLE_LABS);
        // add feature to tnft contract
        ITangibleNFTExt(_tnft).addMetadata(
            _tokenId,
            _features
        );
    }


    // ~ Initial State Test ~

    /// @notice Initial state test.
    function test_basketManager_init_state() public {
        // TODO
    }


    // ~ Unit Tests ~

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
        (IBasket _basket, uint256 basketShares) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            MUMBAI_USDC,
            features,
            address(realEstateTnft),
            1
        );
        vm.stopPrank();

        // Post-state check
        basketsArray = basketManager.getBasketsArray();
        assertEq(basketsArray.length, 1);
        assertEq(basketsArray[0], address(_basket));

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(_basket)), 1);

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

        assertEq(_basket.balanceOf(JOE), basketShares);
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
            MUMBAI_USDC,
            features,
            address(realEstateTnft),
            1
        );
        vm.stopPrank();
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
            MUMBAI_USDC,
            features,
            address(realEstateTnft),
            1
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

    /// @notice This verifies correct logic with the sort method inside BasketsDeployer contract
    function test_basketManager_insertSort() public {

        // Sort testArray1 of size 10.
        uint256[] memory sortedArray = basketManager.sort(testArray1);

        // Verify elements were sorted correctly.
        for (uint256 i; i < sortedArray.length; ++i) {
            assertEq(sortedArray[i], i + 1);
            emit log_uint(sortedArray[i]);
        }

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

        // Create features array of size 4.
        uint256[] memory featuresArray4 = new uint256[](0);

        // Sort
        sortedArray = basketManager.sort(featuresArray4);
        assertEq(sortedArray.length, 0);
    }

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

}