// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// -----------------
// Unreal Deployment
// -----------------

// ~ Core contracts ~

// address constant Unreal_BalanceBatchReader             = 0x28455892e2A277241Ed0534084435fC846e8B650;
// address constant Unreal_MockMatrix                     = 0xCe3B1Bc5225ba37C0B865AAecAa0D09C1128454d;
// address constant Unreal_USDUSDOracle                   = 0xB08Aebe32ca580329479231Dce492bD1410ac123;
// address constant Unreal_ChainLinkOracle                = 0x491EC4AF6a535C0BCAe47B07E068B0358256eF0f;
// address constant Unreal_ChainLinkOracleGBP             = 0x52491A707A93e89ca5e1A39EB77A772a130123Ae;
// address constant Unreal_FactoryV2                      = 0x8EB7C0e7941f47440b30E4aEe065eE35f8737b9B;
// address constant Unreal_CurrencyFeedV2                 = 0xeE49f8D796B96cD5C2a1B89f878729C1bC8FaC49;
// address constant Unreal_GoldOracleTangibleV2           = 0x1bEDF0d13Bf3885D877bA998A270F62839BBf219;
// address constant Unreal_RealtyOracleTangibleV2         = 0x89D98A80c9163799F670DFae87FeD061ece1AA6A;
// address constant Unreal_TangibleV3TokenOracle          = 0x0235e48ACD89AC9A4F1396b56d1Aa0A3Dda24955;
// address constant Unreal_Exchange                       = 0x0fB7a3179a687FA680641cDb346B35012eC4d5e6;
// address constant Unreal_SellFeeDistributorV2           = 0x4003f684C68796B3f6468DA05Dc36c08317F0BEd;
// address constant Unreal_TnftDeployerV2                 = 0xE6cE86e4fB8c1d807C5131393Fc5Ba1DF3Db16a6;
// address constant Unreal_PriceManager                   = 0xB677970C4c29674Fda41c0fEf8fa27da26328357;
// address constant Unreal_RentManagerDeployer            = 0x033CCe79aA75012d3035D5E08320a0B9bA699997;
// address constant Unreal_TNFTMetadata                   = 0xEEaaA573da7A3DD2e6916af92c85680f363bb573;
// address constant Unreal_OnSaleTracker                  = 0xaAB4B3b34f183cdEb1d9d6148d39E82E791340c7;
// address constant Unreal_Marketplace                    = 0xd09Cc86f2d322a75F08006B9f6Dd31776833a492;
// address constant Unreal_TangibleGoldBarsTnft           = 0x054fF50D2af135c91cF36448a217996e31EaCdab;
// address constant Unreal_TangibleREstateTnft            = 0xBff21bda6636BC3A88A99112e7734A489D1f574e;
// address constant Unreal_RentManagerTnft                = 0x62bbB44BbFBb2E68e498c5DE072f7E5F5C7EFb30;
// address constant Unreal_RWAPriceNotificationDispatcher = 0x2e02345761d33C6eB3d75dED3B48D8273E3B6F0c;
// address constant Unreal_RentNotificationDispatcher     = 0x2B4b1efbDbA6Fb554cEe4607C94D1347222D4Ec8;
// address constant Unreal_TangibleProfile                = 0x3F5c095b50d37cf010675D488B4542a4dAa32a90;
// address constant Unreal_TangibleReaderHelper           = 0x4e12BbCEC2BaD4F4bE6a69E34FFEdF1fA6Bef9cf;

address constant Unreal_BalanceBatchReader = 0xB3F1412f8794846881411795C97a835556AEc308;
//address constant Unreal_MockMatrix = 0x131995372479B06532ae2eba3794345CE6EcC2D1;
address constant Unreal_MockMatrix = 0x38bb6F8B295f16a9Ed7778EEaf6954e265894799;
address constant Unreal_USDUSDOracle = 0x1DC675E24e4F42776fBba8988739f9bd026FcE19;
address constant Unreal_ChainLinkOracle = 0x177753854F244e08E69Ec199b313c3Ad85652E1c;
address constant Unreal_ChainLinkOracleGBP = 0xF8A1aD46057c546D2161198049367E4EDCEA6912;
address constant Unreal_FactoryV2 = 0x61d595f7e7E9e08340c7B044499F5A25149b8Fca;
address constant Unreal_CurrencyFeedV2 = 0x6DD9abb56CeCbC6FCB27a716bBECd1eFDfE09f5F;
address constant Unreal_GoldOracleTangibleV2 = 0xdA1879e81C389c6D24B8a34E593c0f7a5970592b;
address constant Unreal_RealtyOracleTangibleV2 = 0xdb14D5c79ae9EEa67A6639e7c5751781b0FE8070;
address constant Unreal_TangibleV3TokenOracle = 0x21AD6dF9ba78778306166BA42Ac06d966119fCE1;
address constant Unreal_Exchange = 0x048c7fB73B9FC96D17E530397213423cd366fC60;
address constant Unreal_SellFeeDistributorV2 = 0x3C2bCaE147F392ed04256EdBfe0E4F3dF9FA6215;
address constant Unreal_TnftDeployerV2 = 0xC0D5B32020427DcbFba6B1c8113FA76aa1701F66;
address constant Unreal_PriceManager = 0x8C6449dF80e4ae3f08B9ce49bCf7b7D0a26255Ae;
address constant Unreal_RentManagerDeployer = 0x71c229c8746B385456AbFf5062D091853f8b57D3;
address constant Unreal_TNFTMetadata = 0x01818dDA4fb4B9CB31f73BA2eAdeb859BCE92a60;
address constant Unreal_OnSaleTracker = 0x108Aa295D899523a58a60BB206565Ada46239f46;
address constant Unreal_Marketplace = 0xad94128fdAB3A2460a26cb485Ab7a35011632E4A;
address constant Unreal_TangibleGoldBarsTnft = 0x8fdbEFFfbdc1c38e4Ff568518fb7a62433D49a20;
address constant Unreal_TangibleREstateTnft = 0xc51073e4c1448448DcbbC6cC0e6E889791d48537;
address constant Unreal_RentManagerTnft = 0xdb856DD051D30F8865EeF3096ac4e17d10bcb5bd;
address constant Unreal_RWAPriceNotificationDispatcher = 0x8872300b137df58B4c2f7493DBE444D475236837;
address constant Unreal_RentNotificationDispatcher = 0xf6D84a171d8584Ce42957fBCFfbe8D04D6e86C57;
address constant Unreal_TangibleProfile = 0x586315D70F45C58B3B66609C164B250E8fC78380;
address constant Unreal_TangibleReaderHelper = 0x3Ff94A28E784930340102d691ecd1F5bD6E33191;

// ~ Baskets ~

// proxies
address constant Unreal_BasketManager          = 0x6ece6fE77AFbC7c47aBcCDF138ff2B09fA66a871;
address constant Unreal_BasketVrfConsumer      = 0x3786761A23E5a10Ff69d53278f42CE548C912152;
// implementation
address constant Unreal_BasketManager_base     = 0x1625f135740Ef1C8720F6102b016335F6bD06914;
address constant Unreal_BasketVrfConsumer_base = 0xbF9f0A9ccC52906caBb2264dB5ac30da33f91064;
address constant Unreal_Basket_base            = 0xE79E3479b897cd626b6BBb58d158C6AAE928047e;

// ~ Deployed Baskets ~