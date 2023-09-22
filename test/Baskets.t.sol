// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

// local contracts
import { Basket } from "../src/Baskets.sol";
import { BasketManager } from "../src/BasketsManager.sol";
import "./utils/Utility.sol";

// tangible contract imports
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { TangibleNFTDeployerV2 } from "@tangible/TangibleNFTDeployerV2.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// https://docs.chain.link/data-feeds/price-feeds/addresses/?network=polygon#Polygon%20Mainnet
// Polygon GBP / USD Price Feed: 0x099a2540848573e94fb1Ca0Fa420b00acbBc845a
// polygon USDC / USD Price Feed: 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7

// chainlinkRWAOracle -> 0x731209585143011778C56BDfaAf87d341adE7C07

// Polygon RPC: https://rpc.ankr.com/polygon


contract BasketsTest is Utility {
    Basket public basket;
    BasketManager public basketManager;

    FactoryProvider public factoryProvider;
    FactoryV2 public factory;
    TangibleNFTV2 public tnft;
    CurrencyFeedV2 public currencyFeed;
    TNFTMetadata public metadata;
    TangiblePriceManagerV2 public priceManager;
    RealtyOracleTangibleV2 public realEstateOracle;
    TNFTMarketplaceV2 public marketplace;
    TangibleNFTDeployerV2 public tnftDeployer;

    //address public constant POLYGON_CHAINLINK_GBPUSD_PRICE_FEED = 0x099a2540848573e94fb1Ca0Fa420b00acbBc845a;
    //address public constant POLYGON_CHAINLINK_USDCUSD_PRICE_FEED = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;

    address public constant TANGIBLE_ORACLE = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
    address public constant TANGIBLE_ORACLE_OWNER = 0x7179B719EEd8c2C60B498d2A2d04f868fb655F22;

    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    uint256 constant public FINGERPRINT = 2222;
    uint256 constant public TNFTTYPE = 1;
    //uint256[] public featuresArray;

    // Actors
    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible Labs Multisig")));

    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        // Deploy Factory
        factory = new FactoryV2(
            address(MUMBAI_USDC),
            TANGIBLE_LABS
        );

        // Deploy Factory Provider
        factoryProvider = new FactoryProvider();
        factoryProvider.initialize(address(factory));

        // Deploy implementation basket contract
        basket = new Basket();

        // Deploy basketManager
        basketManager = new BasketManager(
            address(basket),
            address(factoryProvider)
        );

        // Deplot tnft deployer
        tnftDeployer = new TangibleNFTDeployerV2(
            address(factoryProvider)
        );

        // Deploy Marketplace
        marketplace = new TNFTMarketplaceV2(
            address(factoryProvider)
        );

        // Deploy Currency Feed
        currencyFeed = new CurrencyFeedV2(
            address(factoryProvider)
        );

        // Deploy Price Manager
        priceManager = new TangiblePriceManagerV2(
            address(factoryProvider)
        );

        // Deploy Real Estate Oracle
        realEstateOracle = new RealtyOracleTangibleV2(
            address(factoryProvider),
            address(currencyFeed),
            TANGIBLE_ORACLE
        );

        // Deploy TNFT Metadata
        metadata = new TNFTMetadata(
            address(factoryProvider)
        );

        // Deploy TangibleNFTV2 -> for real estate
        tnft = new TangibleNFTV2(
            address(factoryProvider),
            "TangibleREstate",
            "RLTY", 
            BASE_URI,
            false,
            false,
            false,
            TNFTTYPE
        );


        // ~ configuration ~

        // set contracts on Factory
        factory.setContract(FactoryV2.FACT_ADDRESSES.LABS,            TANGIBLE_LABS);
        factory.setContract(FactoryV2.FACT_ADDRESSES.PRICE_MANAGER,   address(priceManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_META,       address(metadata));
        factory.setContract(FactoryV2.FACT_ADDRESSES.MARKETPLACE,     address(marketplace));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_DEPLOYER,   address(tnftDeployer));
        factory.setContract(FactoryV2.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.CURRENCY_FEED,   address(currencyFeed));


        // Add TNFTType on TNFTMetadata contract
        metadata.addTNFTType(
            TNFTTYPE,
            "RealEstateType1",
            false // TODO: Revisit -> This should be true -> Will deploy rent manager
        );

        // Deploy Basket
        uint256[] memory features = new uint256[](0);
        vm.prank(address(basketManager));
        basket.initialize(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );


        // Create new category with TNFTType on the Factory -> deploying TangibleNFT contract
        vm.prank(TANGIBLE_LABS);
        ITangibleNFT realEstateTnft = factory.newCategory(
            "TangibleREstate",
            "RLTY",
            BASE_URI,
            false,
            false,
            address(realEstateOracle),
            false,
            TNFTTYPE
        );

        // Add fingerprints to TNFT contract
        vm.prank(TANGIBLE_LABS);
        ITangibleNFTExt(address(realEstateTnft)).addFingerprints(_asSingletonArrayUint(FINGERPRINT));

        // Add TNFTType oracle to chainlinkRWA oracle and create item -> stocking item
        vm.startPrank(TANGIBLE_ORACLE_OWNER);
        IPriceOracleExt(TANGIBLE_ORACLE).setTangibleWrapperAddress(address(realEstateOracle));
        IPriceOracleExt(TANGIBLE_ORACLE).createItem(
            FINGERPRINT,  // fingerprint
            500_000_000,  // weSellAt
            0,            // lockedAmount
            1,            // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> Cayman Islands, UK ISO NUMERIC CODE
        );
        vm.stopPrank();

        // create mint voucher
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                               // mintCount
            0,                               // price
            TANGIBLE_LABS,                   // vendor
            JOE,                             // buyer
            FINGERPRINT,                     // fingerprint
            true                             // sendToVender
        );

        // use voucher to obtain TNFT
        vm.prank(TANGIBLE_LABS);
        factory.mint(voucher);

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 1);
        assertEq(realEstateTnft.balanceOf(TANGIBLE_LABS), 0);
        assertEq(realEstateTnft.balanceOf(JOE), 1);

        // labels
        vm.label(address(factory), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(TANGIBLE_ORACLE, "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(factoryProvider), "FACTORY_PROVIDER");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(basket), "BASKET");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(JOE, "JOE");
        
    }


    // ----------
    // Unit Tests
    // ----------


    // ~ Initialize ~

    /// @notice Verifies restrictions and correct state when Basket::initialize() is executed.
    function test_baskets_initialize() public {
        // Deploy implementation basket contract
        Basket _basket = new Basket();
        uint256[] memory features = new uint256[](0);

        // Attempt to initialize a basket with address(0) for factory provider -> revert
        vm.expectRevert("FactoryProvider == address(0)");
        vm.prank(address(basketManager));
        _basket.initialize(
            "Tangible Basket Token",
            "TBT",
            address(0),
            TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        // Execute initialize on basket -> success
        vm.prank(address(basketManager));
        _basket.initialize(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        // Post-state check 1.
        assertEq(_basket.tnftType(), TNFTTYPE);
        assertEq(_basket.deployer(), address(this));
        assertEq(address(_basket.primaryRentToken()), address(MUMBAI_USDC));

        uint256[] memory feats = _basket.getSupportedFeatures();
        assertEq(feats.length, 0);

        // Deploy another basket with features.
        Basket _basket2 = new Basket();
        features = new uint256[](2);
        features[0] = 1;
        features[1] = 2;

        // Execute initialize on basket with features -> success
        vm.prank(address(basketManager));
        _basket2.initialize(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        // Post-state check 2.
        feats = _basket2.getSupportedFeatures();
        assertEq(feats.length, 2);
        assertEq(feats[0], 1);
        assertEq(feats[1], 2);
    }


    // ~ depositTNFT ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT() public {
        assertTrue(true);
    }

}
