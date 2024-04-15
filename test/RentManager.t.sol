// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// tangible contracs
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RentManagerDeployer } from "@tangible/RentManagerDeployer.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { TangibleNFTDeployerV2 } from "@tangible/TangibleNFTDeployerV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";

// interfaces
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// helper imports
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";

/**
 * @title RentManagerTest
 * @author Chase Brown
 * @notice Testing file for RentManager contract.
 */
contract RentManagerTest is Utility {
    RentManager public rentManager;
    TransparentUpgradeableProxy public rentManagerProxy;

    RentManagerDeployer public rentManagerDeployer;
    TransparentUpgradeableProxy public rentManagerDeployerProxy;

    ProxyAdmin public proxyAdmin;

    FactoryV2 public factory;
    TransparentUpgradeableProxy public factoryProxy;
    TangibleNFTV2 public realEstateTnft;
    TransparentUpgradeableProxy public realEstateTnftProxy;
    CurrencyFeedV2 public currencyFeed;
    TransparentUpgradeableProxy public currencyFeedProxy;
    TNFTMetadata public metadata;
    TransparentUpgradeableProxy public metadataProxy;
    TangiblePriceManagerV2 public priceManager;
    TransparentUpgradeableProxy public priceManagerProxy;
    RealtyOracleTangibleV2 public realEstateOracle;
    TransparentUpgradeableProxy public realEstateOracleProxy;
    TangibleNFTDeployerV2 public tnftDeployer;
    TransparentUpgradeableProxy public tnftDeployerProxy;
    TNFTMarketplaceV2 public marketplace;
    TransparentUpgradeableProxy public marketplaceProxy;

    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible labs MultiSig")));
    address public constant CATEGORY_OWNER = address(bytes20(bytes("Category Owner")));

    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    uint256 constant public FINGERPRINT = 2222;
    uint256 constant public TNFTTYPE = 1;

    address public TANGIBLE_ORACLE = Unreal_MockMatrix;
    address public constant ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;

    uint256 public tokenId = 2;

    function setUp() public {

        vm.createSelectFork(UNREAL_RPC_URL);

        proxyAdmin = new ProxyAdmin(address(this));

        // ~ deployment ~

        // Deploy Factory with proxy
        factory = new FactoryV2();
        factoryProxy = new TransparentUpgradeableProxy(
            address(factory),
            address(proxyAdmin),
            abi.encodeWithSelector(FactoryV2.initialize.selector,
                address(UNREAL_USTB),
                TANGIBLE_LABS
            )
        );
        factory = FactoryV2(address(factoryProxy));

        // Deplot tnft deployer with proxy
        tnftDeployer = new TangibleNFTDeployerV2();
        tnftDeployerProxy = new TransparentUpgradeableProxy(
            address(tnftDeployer),
            address(proxyAdmin),
            abi.encodeWithSelector(TangibleNFTDeployerV2.initialize.selector,
                address(factory)
            )
        );
        tnftDeployer = TangibleNFTDeployerV2(address(tnftDeployerProxy));

        // Deploy Marketplace with proxy
        marketplace = new TNFTMarketplaceV2();
        marketplaceProxy = new TransparentUpgradeableProxy(
            address(marketplace),
            address(proxyAdmin),
            abi.encodeWithSelector(TNFTMarketplaceV2.initialize.selector,
                address(factory)
            )
        );
        marketplace = TNFTMarketplaceV2(address(marketplaceProxy));

        // Deploy Currency Feed
        currencyFeed = new CurrencyFeedV2();
        currencyFeedProxy = new TransparentUpgradeableProxy(
            address(currencyFeed),
            address(proxyAdmin),
            abi.encodeWithSelector(CurrencyFeedV2.initialize.selector,
                address(factory)
            )
        );
        currencyFeed = CurrencyFeedV2(address(currencyFeedProxy));

        // Deploy Price Manager with proxy
        priceManager = new TangiblePriceManagerV2();
        priceManagerProxy = new TransparentUpgradeableProxy(
            address(priceManager),
            address(proxyAdmin),
            abi.encodeWithSelector(TangiblePriceManagerV2.initialize.selector,
                address(factory)
            )
        );
        priceManager = TangiblePriceManagerV2(address(priceManagerProxy));

        // Deploy Real Estate Oracle with proxy
        realEstateOracle = new RealtyOracleTangibleV2();
        realEstateOracleProxy = new TransparentUpgradeableProxy(
            address(realEstateOracle),
            address(proxyAdmin),
            abi.encodeWithSelector(RealtyOracleTangibleV2.initialize.selector,
                address(factory),
                address(currencyFeed),
                TANGIBLE_ORACLE
            )
        );
        realEstateOracle = RealtyOracleTangibleV2(address(realEstateOracleProxy));

        // Deploy TNFT Metadata with proxy
        metadata = new TNFTMetadata();
        metadataProxy = new TransparentUpgradeableProxy(
            address(metadata),
            address(proxyAdmin),
            abi.encodeWithSelector(TNFTMetadata.initialize.selector,
                address(factory)
            )
        );
        metadata = TNFTMetadata(address(metadataProxy));

        // Deploy rent manager deployer with proxy
        rentManagerDeployer = new RentManagerDeployer();
        rentManagerDeployerProxy = new TransparentUpgradeableProxy(
            address(rentManagerDeployer),
            address(proxyAdmin),
            abi.encodeWithSelector(RentManagerDeployer.initialize.selector,
                address(factory)
            )
        );
        rentManagerDeployer = RentManagerDeployer(address(rentManagerDeployerProxy));

        // Deploy rent manager with proxy
        rentManager = new RentManager();
        rentManagerProxy = new TransparentUpgradeableProxy(
            address(rentManager),
            address(proxyAdmin),
            abi.encodeWithSelector(RentManager.initialize.selector,
                address(rentManager),
                address(factory)
            )
        );
        rentManager = RentManager(address(rentManagerProxy));


        // set contracts on Factory
        factory.setContract(FactoryV2.FACT_ADDRESSES.LABS,                  TANGIBLE_LABS);
        factory.setContract(FactoryV2.FACT_ADDRESSES.PRICE_MANAGER,         address(priceManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_META,             address(metadata));
        factory.setContract(FactoryV2.FACT_ADDRESSES.MARKETPLACE,           address(marketplace));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_DEPLOYER,         address(tnftDeployer));
        factory.setContract(FactoryV2.FACT_ADDRESSES.CURRENCY_FEED,         address(currencyFeed));
        factory.setContract(FactoryV2.FACT_ADDRESSES.RENT_MANAGER_DEPLOYER, address(rentManagerDeployer));

        // Add TNFTType on TNFTMetadata contract
        metadata.addTNFTType(
            TNFTTYPE,
            "RealEstateType1",
            true
        );

        // Create new category with TNFTType on the Factory -> deploying TangibleNFT contract
        vm.prank(TANGIBLE_LABS);
        ITangibleNFT tnft = factory.newCategory(
            "TangibleREstate",
            "RLTY",
            BASE_URI,
            false,
            false,
            address(realEstateOracle),
            false,
            TNFTTYPE
        );
        realEstateTnft = TangibleNFTV2(address(tnft));

        IRentManager rm = factory.rentManager(tnft);
        rentManager = RentManager(address(rm));

        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(CATEGORY_OWNER);

        // Add fingerprints to TNFT contract
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.addFingerprints(_asSingletonArrayUint(FINGERPRINT));

        // Add TNFTType oracle to chainlinkRWA oracle and create item -> stocking item
        vm.startPrank(ORACLE_OWNER);
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
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(JOE, "JOE");

    }

    
    // ~ Utility ~

    /// @dev local deal to take into account USTB's unique storage layout
    function _deal(address token, address give, uint256 amount) internal {
        // deal doesn't work with USTB since the storage layout is different
        if (token == Unreal_USTB) {
            // update shares balance
            bytes32 USTBStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
            uint256 mapSlot = 2;
            bytes32 slot = keccak256(abi.encode(give, uint256(USTBStorageLocation) + mapSlot));
            vm.store(Unreal_USTB, slot, bytes32(amount));
        }
        // If not rebase token, use normal deal
        else {
            deal(token, give, amount);
        }
    }

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

    /// @notice Verifies correct state changes when RentManager::deposit is executed
    function test_rentManager_deposit() public {
        
        // config
        uint256 amount = 10_000 * 1e18;
        _deal(address(UNREAL_USTB), CATEGORY_OWNER, amount);

        // Pre-state check.
        uint256 preBalOwner = UNREAL_USTB.balanceOf(CATEGORY_OWNER);
        assert(preBalOwner >= amount);
        assertEq(UNREAL_USTB.balanceOf(address(rentManager)), 0);

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
        UNREAL_USTB.approve(address(rentManager), amount);
        rentManager.deposit( // deposit $10,000 with no vesting
            1,
            address(UNREAL_USTB),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // Post-state check.
        assertEq(UNREAL_USTB.balanceOf(CATEGORY_OWNER), preBalOwner - amount);
        assertApproxEqAbs(UNREAL_USTB.balanceOf(address(rentManager)), amount, 1);

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
        assertEq(rentToken, address(UNREAL_USTB));
        assertEq(distributionRunning, true);
    }

    /// @notice Verifies correct state changes when RentManager::claimableRentForTokenBatch is executed for 1 token
    function test_rentManager_claimableRentForTokenBatch_single() public {
        
        // config
        uint256 amount = 10_000 * 1e18;
        _deal(address(UNREAL_USTB), CATEGORY_OWNER, amount);

        // Execute deposit
        vm.startPrank(CATEGORY_OWNER);
        UNREAL_USTB.approve(address(rentManager), amount);
        rentManager.deposit( // deposit $10,000 with no vesting
            1,
            address(UNREAL_USTB),
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
        uint256 amountTNFTs = 10;
        uint256 baseDeposit = 10_000 * 1e18;
        uint256 amount = baseDeposit * amountTNFTs;

        _deal(address(UNREAL_USTB), CATEGORY_OWNER, amount);

        // create tokens
        uint256[] memory tokenIds = new uint256[](amountTNFTs);
        for (uint256 i; i < amountTNFTs; ++i) {
            tokenIds[i] = _createToken(FINGERPRINT);
        }

        // Execute deposit
        for (uint256 i; i < amountTNFTs; ++i) {
            vm.startPrank(CATEGORY_OWNER);
            UNREAL_USTB.approve(address(rentManager), baseDeposit);
            rentManager.deposit( // deposit $10,000 with no vesting
                tokenIds[i],
                address(UNREAL_USTB),
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
            assertApproxEqAbs(claimables[i], baseDeposit/2, 1);
            totalRent += claimables[i];
        }

        assertEq(totalRent, amount/2);
    }

    /// @notice Verifies correct state changes when RentManager::claimRentForTokenBatch is executed for 1 token
    function test_rentManager_claimRentForTokenBatch_single() public {
        
        // config
        uint256 amount = 10_000 * 1e18;
        _deal(address(UNREAL_USTB), CATEGORY_OWNER, amount);
        _deal(address(UNREAL_USTB), address(rentManager), 1);

        // Execute deposit
        vm.startPrank(CATEGORY_OWNER);
        UNREAL_USTB.approve(address(rentManager), amount);
        rentManager.deposit( // deposit $10,000 with no vesting
            1,
            address(UNREAL_USTB),
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
        assertEq(UNREAL_USTB.balanceOf(JOE), 0);

        // Execute claimRentForTokenBatch
        vm.prank(JOE);
        uint256[] memory claimed = rentManager.claimRentForTokenBatch(_asSingletonArrayUint(1));

        // Post-state check
        claimables = rentManager.claimableRentForTokenBatch(_asSingletonArrayUint(1));
        assertEq(claimables[0], 0);
        assertEq(UNREAL_USTB.balanceOf(JOE), amount);
        assertEq(claimed[0], amount);
    }

    /// @notice Verifies correct state changes when RentManager::claimRentForTokenBatch is executed for multiple tokens
    function test_rentManager_claimRentForTokenBatch_multiple() public {
        
        // config
        uint256 amountTNFTs = 10;
        uint256 baseDeposit = 10_000 * 1e18;
        uint256 amount = baseDeposit * amountTNFTs;

        _deal(address(UNREAL_USTB), CATEGORY_OWNER, amount);

        // create tokens
        uint256[] memory tokenIds = new uint256[](amountTNFTs);
        for (uint256 i; i < amountTNFTs; ++i) {
            tokenIds[i] = _createToken(FINGERPRINT);
        }

        // Execute deposit
        for (uint256 i; i < amountTNFTs; ++i) {
            vm.startPrank(CATEGORY_OWNER);
            UNREAL_USTB.approve(address(rentManager), baseDeposit);
            rentManager.deposit( // deposit $10,000 with no vesting
                tokenIds[i],
                address(UNREAL_USTB),
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
        assertEq(UNREAL_USTB.balanceOf(JOE), 0);
        uint256 totalRentClaimable;
        for (uint256 i; i < claimables.length; ++i) {
            assertEq(claimables[i], baseDeposit/2);
            totalRentClaimable += claimables[i];
        }
        assertEq(totalRentClaimable, amount/2);
        assertEq(totalRentClaimable, rentManager.claimableRentForTokenBatchTotal(tokenIds));

        // Execute claimRentForTokenBatch
        vm.prank(JOE);
        uint256[] memory claimed = rentManager.claimRentForTokenBatch(tokenIds);

        // Post-state check 2
        assertApproxEqAbs(UNREAL_USTB.balanceOf(JOE), amount/2, 100);
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(claimed[i], baseDeposit/2);
        }
    }
  
}