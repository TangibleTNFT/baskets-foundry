// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

// local contracts
import { Basket } from "../src/Baskets.sol";
import { BasketDeployer } from "../src/BasketsDeployer.sol";
import "./Utility.sol";

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


contract BasketsTest is Test {
    Basket public basket;
    BasketDeployer public basketDeployer;

    FactoryProvider public factoryProvider;
    FactoryV2 public factory;
    TangibleNFTV2 public tnft;
    CurrencyFeedV2 public currencyFeed;
    TNFTMetadata public metadata;
    TangiblePriceManagerV2 public priceManager;
    RealtyOracleTangibleV2 public realEstateOracle;
    TNFTMarketplaceV2 public marketplace;
    TangibleNFTDeployerV2 public tnftDeployer;

    address public constant USDC_MAINNET = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    address public constant POLYGON_CHAINLINK_GBPUSD_PRICE_FEED = 0x099a2540848573e94fb1Ca0Fa420b00acbBc845a;
    address public constant POLYGON_CHAINLINK_USDCUSD_PRICE_FEED = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;

    address public constant TANGIBLE_ORACLE = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
    address public constant TANGIBLE_ORACLE_OWNER = 0x7179B719EEd8c2C60B498d2A2d04f868fb655F22;

    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    uint256 constant public FINGERPRINT = 2222;
    uint256 constant public TNFTTYPE = 1;
    uint256[] public featuresArray;

    // Actors
    address public constant JOE = address(bytes20(bytes("Joe")));
    address public constant ADMIN = address(bytes20(bytes("Admin")));
    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible Labs Multisig")));

    function setUp() public {

        // Deploy Factory
        factory = new FactoryV2(
            USDC,
            TANGIBLE_LABS
        );

        // Deploy Factory Provider
        factoryProvider = new FactoryProvider();
        factoryProvider.initialize(address(factory));

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

        // Deploy Basket
        basket = new Basket(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            TNFTTYPE,
            address(currencyFeed),
            address(metadata)
        );


        // ~ configuration ~

        factory.setContract(FactoryV2.FACT_ADDRESSES.LABS, TANGIBLE_LABS);
        factory.setContract(FactoryV2.FACT_ADDRESSES.PRICE_MANAGER, address(priceManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_META, address(metadata));
        factory.setContract(FactoryV2.FACT_ADDRESSES.MARKETPLACE, address(marketplace));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_DEPLOYER, address(tnftDeployer));

        metadata.addTNFTType(
            TNFTTYPE,
            "RealEstateType1",
            false // TODO: Revisit -> This should be true -> Will deploy rent manager
        );

        vm.prank(TANGIBLE_LABS);
        ITangibleNFT newTnft = factory.newCategory(
            "TangibleREstate",
            "RLTY",
            BASE_URI,
            false,
            false,
            address(realEstateOracle),
            false,
            TNFTTYPE
        );

        vm.prank(TANGIBLE_LABS);
        newTnft.addFingerprints(_asSingletonArrayUint(FINGERPRINT));

        vm.startPrank(TANGIBLE_ORACLE_OWNER);
        // ITangibleOracle(TANGIBLE_ORACLE).transferOwnership(TANGIBLE_LABS);
        // vm.startPrank(TANGIBLE_LABS);
        // ITangibleOracle(TANGIBLE_ORACLE).acceptOwnership();
        IPriceOracleExt(TANGIBLE_ORACLE).setTangibleWrapperAddress(address(realEstateOracle));
        IPriceOracleExt(TANGIBLE_ORACLE).createItem(
            FINGERPRINT,  // fingerprint
            50000000,     // weSellAt
            0,            // lockedAmount
            1,            // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> Cayman Islands, UK ISO NUMERIC CODE
        );
        vm.stopPrank();

        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(address(newTnft)),  // token
            1,                               // mintCount
            0,                               // price
            TANGIBLE_LABS,                   // vendor
            JOE,                             // buyer
            FINGERPRINT,                     // fingerprint
            true                             // sendToVender
        );

        vm.prank(TANGIBLE_LABS);
        factory.mint(voucher);
        
    }


    // ~ Utility ~ 

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }


    // ~ Initial State Test ~

    /// @notice Initial state test.
    function test_baskets_init_state() public {}


    // ~ Unit Tests ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT() public {
        assertTrue(true);
    }

}
