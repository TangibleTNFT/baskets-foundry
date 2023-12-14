// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// -----------------
// Unreal Deployment
// -----------------

// ~ Core contracts ~

address constant Unreal_BalanceBatchReader             = 0x28455892e2A277241Ed0534084435fC846e8B650;
address constant Unreal_MockMatrix                     = 0xCe3B1Bc5225ba37C0B865AAecAa0D09C1128454d;
address constant Unreal_USDUSDOracle                   = 0xB08Aebe32ca580329479231Dce492bD1410ac123;
address constant Unreal_ChainLinkOracle                = 0x491EC4AF6a535C0BCAe47B07E068B0358256eF0f;
address constant Unreal_ChainLinkOracleGBP             = 0x52491A707A93e89ca5e1A39EB77A772a130123Ae;
address constant Unreal_FactoryV2                      = 0x8EB7C0e7941f47440b30E4aEe065eE35f8737b9B;
address constant Unreal_CurrencyFeedV2                 = 0xeE49f8D796B96cD5C2a1B89f878729C1bC8FaC49;
address constant Unreal_GoldOracleTangibleV2           = 0x1bEDF0d13Bf3885D877bA998A270F62839BBf219;
address constant Unreal_RealtyOracleTangibleV2         = 0x89D98A80c9163799F670DFae87FeD061ece1AA6A;
address constant Unreal_TangibleV3TokenOracle          = 0x0235e48ACD89AC9A4F1396b56d1Aa0A3Dda24955;
address constant Unreal_Exchange                       = 0x0fB7a3179a687FA680641cDb346B35012eC4d5e6;
address constant Unreal_SellFeeDistributorV2           = 0x4003f684C68796B3f6468DA05Dc36c08317F0BEd;
address constant Unreal_TnftDeployerV2                 = 0xE6cE86e4fB8c1d807C5131393Fc5Ba1DF3Db16a6;
address constant Unreal_PriceManager                   = 0xB677970C4c29674Fda41c0fEf8fa27da26328357;
address constant Unreal_RentManagerDeployer            = 0x033CCe79aA75012d3035D5E08320a0B9bA699997;
address constant Unreal_TNFTMetadata                   = 0xEEaaA573da7A3DD2e6916af92c85680f363bb573;
address constant Unreal_OnSaleTracker                  = 0xaAB4B3b34f183cdEb1d9d6148d39E82E791340c7;
address constant Unreal_Marketplace                    = 0xd09Cc86f2d322a75F08006B9f6Dd31776833a492;
address constant Unreal_TangibleGoldBarsTnft           = 0x054fF50D2af135c91cF36448a217996e31EaCdab;
address constant Unreal_TangibleREstateTnft            = 0xBff21bda6636BC3A88A99112e7734A489D1f574e;
address constant Unreal_RentManagerTnft                = 0x62bbB44BbFBb2E68e498c5DE072f7E5F5C7EFb30;
address constant Unreal_RWAPriceNotificationDispatcher = 0x2e02345761d33C6eB3d75dED3B48D8273E3B6F0c;
address constant Unreal_RentNotificationDispatcher     = 0x2B4b1efbDbA6Fb554cEe4607C94D1347222D4Ec8;
address constant Unreal_TangibleProfile                = 0x3F5c095b50d37cf010675D488B4542a4dAa32a90;
address constant Unreal_TangibleReaderHelper           = 0x4e12BbCEC2BaD4F4bE6a69E34FFEdF1fA6Bef9cf;

// ~ Baskets ~

// proxies
address constant Unreal_BasketManager          = address(0);
address constant Unreal_BasketVrfConsumer      = address(0);
// implementation
address constant Unreal_BasketManager_base     = address(0);
address constant Unreal_BasketVrfConsumer_base = address(0);
address constant Unreal_Basket_base            = address(0);

// ~ Deployed Baskets ~