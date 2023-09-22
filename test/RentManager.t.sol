// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RentManagerDeployer } from "@tangible/RentManagerDeployer.sol";
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { TangibleNFTDeployerV2 } from "@tangible/TangibleNFTDeployerV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";

import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

contract RentManagerTest is Utility {
    RentManager public rentManager;
    RentManagerDeployer public rentManagerDeployer;

    FactoryProvider public factoryProvider;
    FactoryV2 public factory;
    TangibleNFTV2 public realEstateTnft;
    CurrencyFeedV2 public currencyFeed;
    TNFTMetadata public metadata;
    TangiblePriceManagerV2 public priceManager;
    RealtyOracleTangibleV2 public realEstateOracle;
    TangibleNFTDeployerV2 public tnftDeployer;
    TNFTMarketplaceV2 public marketplace;

    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible labs MultiSig")));
    address public constant CATEGORY_OWNER = address(bytes20(bytes("Category Owner")));

    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    uint256 constant public FINGERPRINT = 2222;
    uint256 constant public TNFTTYPE = 1;

    address public constant TANGIBLE_ORACLE = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
    address public constant TANGIBLE_ORACLE_OWNER = 0x7179B719EEd8c2C60B498d2A2d04f868fb655F22;

    uint256 public tokenId = 2;

    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        // ~ deployment ~

        // Deploy Factory
        factory = new FactoryV2(
            address(MUMBAI_USDC),
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
        realEstateTnft = new TangibleNFTV2(
            address(factoryProvider),
            "TangibleREstate",
            "RLTY", 
            BASE_URI,
            false,
            false,
            false,
            TNFTTYPE
        );

        rentManager = new RentManager(
            address(realEstateTnft),
            address(factoryProvider)
        );


        // set contracts on Factory
        factory.setContract(FactoryV2.FACT_ADDRESSES.LABS,            TANGIBLE_LABS);
        factory.setContract(FactoryV2.FACT_ADDRESSES.PRICE_MANAGER,   address(priceManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_META,       address(metadata));
        factory.setContract(FactoryV2.FACT_ADDRESSES.MARKETPLACE,     address(marketplace));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_DEPLOYER,   address(tnftDeployer));
        factory.setContract(FactoryV2.FACT_ADDRESSES.CURRENCY_FEED,   address(currencyFeed));

        // Add TNFTType on TNFTMetadata contract
        metadata.addTNFTType(
            TNFTTYPE,
            "RealEstateType1",
            false // TODO: Revisit -> This should be true -> Will deploy rent manager
        );

        // Create new category with TNFTType on the Factory -> deploying TangibleNFT contract
        factory.setCategory(
            "TangibleREstate",
            realEstateTnft,
            rentManager,
            address(realEstateOracle),
            CATEGORY_OWNER
        );

        vm.prank(CATEGORY_OWNER);
        rentManager.updateDepositor(CATEGORY_OWNER);

        // Add fingerprints to TNFT contract
        realEstateTnft.addFingerprints(_asSingletonArrayUint(FINGERPRINT));

        // Add TNFTType oracle to chainlinkRWA oracle and create item -> stocking item
        vm.startPrank(TANGIBLE_ORACLE_OWNER);
        IPriceOracleExt(TANGIBLE_ORACLE).setTangibleWrapperAddress(address(realEstateOracle));
        IPriceOracleExt(TANGIBLE_ORACLE).createItem(
            FINGERPRINT,  // fingerprint
            500_000_000,  // weSellAt
            0,            // lockedAmount
            10_000,       // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> Cayman Islands, UK ISO NUMERIC CODE
        );
        vm.stopPrank();

        // create mint voucher
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            2,                               // mintCount
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
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 2);
        assertEq(realEstateTnft.balanceOf(TANGIBLE_LABS), 0);
        assertEq(realEstateTnft.balanceOf(JOE), 2);

        // labels
        vm.label(address(factory), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(TANGIBLE_ORACLE, "CHAINLINK_ORACLE");
        vm.label(CATEGORY_OWNER, "CATEGORY OWNER");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(factoryProvider), "FACTORY_PROVIDER");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(JOE, "JOE");

    }

    
    // ~ Utility ~

    function _createToken(uint256 fingerprint) internal returns (uint256) {

        uint256 preBal = realEstateTnft.balanceOf(JOE);

        // create mint voucher
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                               // mintCount
            0,                               // price
            TANGIBLE_LABS,                   // vendor
            JOE,                             // buyer
            fingerprint,                     // fingerprint
            true                             // sendToVender
        );

        // use voucher to obtain TNFT
        vm.prank(TANGIBLE_LABS);
        factory.mint(voucher);

        ++tokenId;

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, tokenId);

        assertEq(realEstateTnft.balanceOf(JOE), preBal + 1);

        return tokenId;
    }


    // ~ Unit Tests ~

    // TODO: Test deposit, claimableRentForTokenBatch, and claimRentForTokenBatch

    /// @notice Verifies correct state changes when RentManager::deposit is executed
    function test_rentManager_deposit() public {
        
        // config
        uint256 amount = 10_000 * USD;
        deal(address(MUMBAI_USDC), CATEGORY_OWNER, amount);

        // Pre-state check.
        assertEq(MUMBAI_USDC.balanceOf(CATEGORY_OWNER), amount);
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 0);

        (
            uint256 depositAmount,
            uint256 claimedAmount,
            uint256 claimedAmountTotal,
            uint256 unclaimedAmount,
            uint256 depositTime,
            uint256 endTime,
            address rentToken,
            bool distributionRunning
        ) = rentManager.rentInfo(1);

        assertEq(depositAmount, 0);
        assertEq(claimedAmount, 0);
        assertEq(claimedAmountTotal, 0);
        assertEq(unclaimedAmount, 0);
        assertEq(depositTime, 0);
        assertEq(endTime, 0);
        assertEq(rentToken, address(0));
        assertEq(distributionRunning, false);

        // Execute deposit
        vm.startPrank(CATEGORY_OWNER);
        MUMBAI_USDC.approve(address(rentManager), amount);
        rentManager.deposit( // deposit $10,000 with no vesting
            1,
            address(MUMBAI_USDC),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // Post-state check.
        assertEq(MUMBAI_USDC.balanceOf(CATEGORY_OWNER), 0);
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), amount);

        (
            depositAmount,
            claimedAmount,
            claimedAmountTotal,
            unclaimedAmount,
            depositTime,
            endTime,
            rentToken,
            distributionRunning
        ) = rentManager.rentInfo(1);

        assertEq(depositAmount, amount);
        assertEq(claimedAmount, 0);
        assertEq(claimedAmountTotal, 0);
        assertEq(unclaimedAmount, 0);
        assertEq(depositTime, block.timestamp);
        assertEq(endTime, block.timestamp + 1);
        assertEq(rentToken, address(MUMBAI_USDC));
        assertEq(distributionRunning, true);
    }

    /// @notice Verifies correct state changes when RentManager::claimableRentForTokenBatch is executed for 1 token
    function test_rentManager_claimableRentForTokenBatch_single() public {
        
        // config
        uint256 amount = 10_000 * USD;
        deal(address(MUMBAI_USDC), CATEGORY_OWNER, amount);

        // Execute deposit
        vm.startPrank(CATEGORY_OWNER);
        MUMBAI_USDC.approve(address(rentManager), amount);
        rentManager.deposit( // deposit $10,000 with no vesting
            1,
            address(MUMBAI_USDC),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // Execute claimableRentForTokenBatch with 1 token
        uint256[] memory claimables = rentManager.claimableRentForTokenBatch(_asSingletonArrayUint(1));

        // Post-state check 1
        assertEq(claimables[0], 0);

        // Skip 1 second -> vesting endTime
        skip(1);

        // Execute claimableRentForTokenBatch again, when vesting is over
        claimables = rentManager.claimableRentForTokenBatch(_asSingletonArrayUint(1));

        // Post-state check 2
        assertEq(claimables[0], amount);
    }

    /// @notice Verifies correct state changes when RentManager::claimableRentForTokenBatch is executed for multiple tokens
    function test_rentManager_claimableRentForTokenBatch_multiple() public {
        
        // config
        uint256 amountTNFTs = 100;
        uint256 baseDeposit = 10_000 * USD;
        uint256 amount = baseDeposit * amountTNFTs;

        deal(address(MUMBAI_USDC), CATEGORY_OWNER, amount);

        // create tokens
        uint256[] memory tokenIds = new uint256[](amountTNFTs);
        for (uint256 i; i < amountTNFTs; ++i) {
            tokenIds[i] = _createToken(FINGERPRINT);
        }

        // Execute deposit
        for (uint256 i; i < amountTNFTs; ++i) {
            vm.startPrank(CATEGORY_OWNER);
            MUMBAI_USDC.approve(address(rentManager), baseDeposit);
            rentManager.deposit( // deposit $10,000 with no vesting
                tokenIds[i],
                address(MUMBAI_USDC),
                baseDeposit,
                0,
                block.timestamp + (10 days),
                true
            );
            vm.stopPrank();
        }

        // Execute claimableRentForTokenBatch with 1 token
        uint256[] memory claimables = rentManager.claimableRentForTokenBatch(tokenIds); // 1000 TNFTs -> 1.1M gas (passable)

        // Post-state check 1
        assertEq(claimables.length, amountTNFTs);
        assertEq(claimables[0], 0);

        // Skip to helf vesting period
        vm.warp(block.timestamp + (5 days));

        // Execute claimableRentForTokenBatch
        claimables = rentManager.claimableRentForTokenBatch(tokenIds);

        // Post-state check 2
        uint256 totalRent;
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(claimables[i], baseDeposit/2);
            totalRent += claimables[i];
        }

        assertEq(totalRent, amount/2);
    }

    /// @notice Verifies correct state changes when RentManager::claimRentForTokenBatch is executed for 1 token
    function test_rentManager_claimRentForTokenBatch_single() public {
        
        // config
        uint256 amount = 10_000 * USD;
        deal(address(MUMBAI_USDC), CATEGORY_OWNER, amount);

        // Execute deposit
        vm.startPrank(CATEGORY_OWNER);
        MUMBAI_USDC.approve(address(rentManager), amount);
        rentManager.deposit( // deposit $10,000 with no vesting
            1,
            address(MUMBAI_USDC),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // skip to end of vesting time
        skip(1);

        // Pre-state check
        uint256[] memory claimables = rentManager.claimableRentForTokenBatch(_asSingletonArrayUint(1));
        assertEq(claimables[0], amount);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        // Execute claimRentForTokenBatch
        vm.prank(JOE);
        uint256[] memory claimed = rentManager.claimRentForTokenBatch(_asSingletonArrayUint(1));

        // Post-state check
        claimables = rentManager.claimableRentForTokenBatch(_asSingletonArrayUint(1));
        assertEq(claimables[0], 0);
        assertEq(MUMBAI_USDC.balanceOf(JOE), amount);
        assertEq(claimed[0], amount);
    }

    /// @notice Verifies correct state changes when RentManager::claimRentForTokenBatch is executed for multiple tokens
    function test_rentManager_claimRentForTokenBatch_multiple() public {
        
        // config
        uint256 amountTNFTs = 100;
        uint256 baseDeposit = 10_000 * USD;
        uint256 amount = baseDeposit * amountTNFTs;

        deal(address(MUMBAI_USDC), CATEGORY_OWNER, amount);

        // create tokens
        uint256[] memory tokenIds = new uint256[](amountTNFTs);
        for (uint256 i; i < amountTNFTs; ++i) {
            tokenIds[i] = _createToken(FINGERPRINT);
        }

        // Execute deposit
        for (uint256 i; i < amountTNFTs; ++i) {
            vm.startPrank(CATEGORY_OWNER);
            MUMBAI_USDC.approve(address(rentManager), baseDeposit);
            rentManager.deposit( // deposit $10,000 with no vesting
                tokenIds[i],
                address(MUMBAI_USDC),
                baseDeposit,
                0,
                block.timestamp + (10 days),
                true
            );
            vm.stopPrank();
        }

        // Skip to half vesting period
        vm.warp(block.timestamp + (5 days));

        // Post-state check 1
        uint256[] memory claimables = rentManager.claimableRentForTokenBatch(tokenIds); // 1000 TNFTs -> 1.1M gas (passable)
        assertEq(claimables.length, amountTNFTs);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);
        uint256 totalRentClaimable;
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(claimables[i], baseDeposit/2);
            totalRentClaimable += claimables[i];
        }
        assertEq(totalRentClaimable, amount/2);

        // Execute claimRentForTokenBatch
        vm.prank(JOE);
        uint256[] memory claimed = rentManager.claimRentForTokenBatch(tokenIds);

        // Post-state check 2
        assertEq(MUMBAI_USDC.balanceOf(JOE), amount/2);
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(claimed[i], baseDeposit/2);
        }
    }
  
}