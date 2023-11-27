// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// -----------------
// Mumbai Deployment
// -----------------


// Old MockMatrix Addresses:
// - 0x58f44400e9B05582c2fA954a5d2622e3EDf918dD;
// - 0xBE6664FC5DcE36F3dA4fc256Faa92930C276F76c;

// ~ Core contracts ~

// address constant Mumbai_BalanceBatchReader             = 0xc4b351F7e9597Ba82B3Ad726A573a0e9492413ff;
// address constant Mumbai_MockMatrix                     = 0xf4f41647554c43927ae2C3806D03aD864D19A1d9;
// address constant Mumbai_USDUSDOracle                   = 0x9e92B33DbF3416Ce2eF8b8d9036A8F84cC30c9b7;
// address constant Mumbai_ChainLinkOracle                = 0x077306ED1b3a206C1f226Ad5fa3234ce0A4Fb8CC;
// address constant Mumbai_ChainLinkOracleGBP             = 0xb24Ce57c96d27690Ae68aa77656a821d5A53b5eB;
// address constant Mumbai_FactoryV2                      = 0x1d5De3D5C8917C4FeF87388E410a73F52FAa7A7C;
// address constant Mumbai_CurrencyFeedV2                 = 0xE47B7834fE12c04C900A5776E58743A9133E93e1;
// address constant Mumbai_GoldOracleTangibleV2           = 0xA9327c33988DDf00463a531FB8624A3b1f85c81c;
// address constant Mumbai_RealtyOracleTangibleV2         = 0x5e0E7A16573fD5B1a5321D60873501484a9b5AD7;
// address constant Mumbai_TangibleV3TokenOracle          = 0x6308767381DbC1c9933FfE48bcD72aA85831A73c;
// address constant Mumbai_Exchange                       = 0x4465f1BC5B008D4444eb746e649Cddd0c99F5DA4;
// address constant Mumbai_SellFeeDistributorV2           = 0xbF7f5f1eeEE2342921860d36a25Be7ECf39a06F6;
// address constant Mumbai_TnftDeployerV2                 = 0x07d3A93e8F3359125FFa1eb587D5a9c61B455cE4;
// address constant Mumbai_PriceManager                   = 0x04F50c2E4B131531D11FE782c6a64C590e62001F;
// address constant Mumbai_RentManagerDeployer            = 0x91B4Cb636B2DD157E5Bda622839359fEa2d42f3F;
// address constant Mumbai_TNFTMetadata                   = 0x7CF9EdB9F76E27CaE942bd81beC8bBd920b023DB;
// address constant Mumbai_OnSaleTracker                  = 0x8e043D4DC0155755a63f89aB53C29b3a6f34F0dC;
// address constant Mumbai_Marketplace                    = 0xeAabDEC8086649D81f006aCBf49214EEe67516d1;
// address constant Mumbai_TangibleGoldBarsTnft           = 0xa0ee5F42EffF80e4e9229c090A89aed6c585EaAa;
// address constant Mumbai_TangibleREstateTnft            = 0x0d4a53AE894C8E109b55cAD5F840920d46E00B93;
// address constant Mumbai_RentManagerTnft                = 0x291fd3A35F2712d14d2f9D678BbA71bd226E7f69;
// address constant Mumbai_RWAPriceNotificationDispatcher = 0x3eD35368386f925105A89975FFC8743bcCEd3EcB;
// address constant Mumbai_RentNotificationDispatcher     = 0x5aB34991E0695AfdFDBED0Dc97FBeB78C43067Ba;
// address constant Mumbai_TangibleProfile                = 0x7aa7D872B335eF8c1f5eB21C8C9Dc4d05Bf3AABF;
// address constant Mumbai_TangibleReaderHelper           = 0xbb3833446316f92b1D657146b1fB7529ee130C32;

address constant Mumbai_BalanceBatchReader             = 0x97cF8d8e194C5A6E77c0b469C070df84c71e637b;
address constant Mumbai_MockMatrix                     = 0x1Cd48C464e9E9e8E3676fCF5339fF44C91D15B3B;
address constant Mumbai_USDUSDOracle                   = 0xc0026BD217e6dAB015Ab92910d6e563Ec0BEdcB0;
address constant Mumbai_ChainLinkOracle                = 0x638265de853bC8aA0c5D45eEF82cb9192836f12E;
address constant Mumbai_ChainLinkOracleGBP             = 0xfdDB736F020275e129f21bE1314044fEfBBcF6e4;
address constant Mumbai_FactoryV2                      = 0x9126c87E590818dAf9a4B30C75d44B4000783B17;
address constant Mumbai_CurrencyFeedV2                 = 0xE5B0699DfB8253eD8e82AC43e8a3E3C0fe8AAfF5;
address constant Mumbai_GoldOracleTangibleV2           = 0x1DeB16e9f722AA1355cBcDC4028A269C2102012d;
address constant Mumbai_RealtyOracleTangibleV2         = 0xB504c09B8D86BCFDB91170A54b20c968F43C9f07;
address constant Mumbai_TangibleV3TokenOracle          = 0xAE1823a60fFCc442069bD834116e82b066f32CAA;
address constant Mumbai_Exchange                       = 0x874b03Bf7a482c3Ef1F67f315EF6daB91953419e;
address constant Mumbai_SellFeeDistributorV2           = 0x9acdba8Fa4B95cC4fB1180C966AC8235Cc2f3c79;
address constant Mumbai_TnftDeployerV2                 = 0xE9e20d81901a3FfC3e7Fe7E81921E93DfC27bdf1;
address constant Mumbai_PriceManager                   = 0x6Aa97041244BA0E1c8b8D0Fa04542cfD0b5379cD;
address constant Mumbai_RentManagerDeployer            = 0xD23fE1403340df0389d3bbbcFBE9d9C8DB1A5be5;
address constant Mumbai_TNFTMetadata                   = 0x7179DB2712583bdb1889625DCF4bf6808c55248c;
address constant Mumbai_OnSaleTracker                  = 0x39eD4fA2D8a59C35D463D7810594Eb0D9a2f1289;
address constant Mumbai_Marketplace                    = 0x5Cf739Ae13f9b77492e4Cc6B5194AE464f8b3865;
address constant Mumbai_TangibleGoldBarsTnft           = 0x3B78997bCEf54E8c8684214e04277cef4a3B6E91;
address constant Mumbai_TangibleREstateTnft            = 0xe3A81350e42DF609C52b94410FE2c25A7f7e6B31;
address constant Mumbai_RentManagerTnft                = 0xA49b220b083b4510b32219BF8D3ea4A8888d4bEB;
address constant Mumbai_RWAPriceNotificationDispatcher = 0xDDFD601C2fD50479EC829B9dF3b4fd7aDb0E8A2F;
address constant Mumbai_RentNotificationDispatcher     = 0x1D967a4AE4117D8DBDBB73059025129C6505709a;
address constant Mumbai_TangibleProfile                = 0x74268E0655890E3cB66e60DE9fF48161e96f6094;
address constant Mumbai_TangibleReaderHelper           = 0xD1840163094C94e9EA3d0DeCbA17A0c7b01dCd3e;

// ~ Baskets ~

// proxies
address constant Mumbai_BasketManager     = 0xcDCB34206b12015F75Ae1972e718c53b7278501C;
address constant Mumbai_BasketVrfConsumer = 0xf75ABF187E67489a7e454E601E86702Eb18cA8c7;

// implementation
address constant Mumbai_BasketImplementation            = 0xA7337e01FB60B4b144cb4ce106101FDe6E9eCf52;
address constant Mumbai_BasketManagerImplementation     = 0x74C6D273A7877C87703b7c4D5eFB658169072cc7;
address constant Mumbai_BasketVrfConsumerImplementation = 0x6D2bA31d45Dbcf461c02eD43d8D97DD72Ccbd79F;

// mock
address constant Mumbai_MockVrfCoordinator = 0x4CA126ca3f8298cD0ec7Fefe2833a7B51e850A45;

// ~ Deployed Baskets ~

address constant Mumbai_Basket_1 = 0x9Df071d66ebaE7cBa85339cFf36D0313c781210E;