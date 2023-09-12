// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// ~ Mumbai Deployment 1 ~

// address constant Mumbai_BalanceBatchReader     = 0x0f08a4b9552190cBaF160cE1114d3Cf74960cc88;
// address constant Mumbai_ChainLinkOracle        = 0xB548edFC1592d16520D76020FEAc95364A7e177d;
// address constant Mumbai_ChainLinkOracleGBP     = 0x3D2657603F37A15c26c62C403c6C61DA58f060B0;
// address constant Mumbai_FactoryV2              = 0x94fbC8cebB514d9955Be361a45e64Dd3280f6804;
// address constant Mumbai_FactoryProvider        = 0xc5B3419E3F26EffC87ffD25C3904c7b709D860b3;
// address constant Mumbai_CurrencyFeedV2         = 0x49c12660D66c3E4C0cE86bBd99E603E3cDA33BA8;
// address constant Mumbai_GoldOracleTangibleV2   = 0x8f1307e6762e1e11C3084cc9a3e9c743fe65BAaD;
// address constant Mumbai_RealtyOracleTangibleV2 = 0x5DfF047286D16c7c05aAcDf26ad9C9d0803Ca985;
// address constant Mumbai_TangibleV3TokenOracle  = 0xE97CA96cD34bC1eF7E978c29Bd88564E7A772e19;
// address constant Mumbai_Exchange               = 0xc472644D8123E61300227958A566Af4c2eB6d775;
// address constant Mumbai_SellFeeDistributorV2   = 0xA73aE76f6602042733C13265131acA63B2482C39;
// address constant Mumbai_TnftDeployerV2         = 0x7aE198C21dE5fb3f6cdE704021E4C389af98E5A9;
// address constant Mumbai_PriceManager           = 0xf1409DfA93bB027f13521b43A5e276e570A5d799;
// address constant Mumbai_RentManagerDeployer    = 0x6953adF29d3153C22Dc4f148129BE4e45896ADC5;
// address constant Mumbai_TNFTMetadata           = 0xB50C4c6986B951EBa89Ee531B87FAbfc72138389;
// address constant Mumbai_OnSaleTracker          = 0xc5bdaE7413F4E45C7cE241451b45b74a504e2119;
// address constant Mumbai_Marketplace            = 0xD5b454baB4A25D2247e059bF2268bc9681FEA110;
// address constant Mumbai_TangibleGoldBarsTnft   = 0xe9aD5421a1DB07287350D34C29D649CE1fFf1fb4;
// address constant Mumbai_TangibleREstateTnft    = 0xc056d4d7Bdb5b632b2cdfDA81C0A0E98567e5C77;
// address constant Mumbai_TangibleProfile        = 0x917F2eB11F252cb45B241D625D50b2E22AA1F882;
// address constant Mumbai_TangibleReaderHelper   = 0x99924F7CDBF56AdC1505Cf58f3E94cF35b637E99;
// address constant Mumbai_ChainlinkOracle        = 0xbE2F59A77eb5D38FE4E14c8E5284e72E07f74cee;

// ~ Mumbai Deployment 2 ~

// address constant Mumbai_BalanceBatchReader     = 0x6A1467D4c8dDe056424d2221331886D71Fe8cBf0;
// address constant Mumbai_MockMatrix             = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
// address constant Mumbai_USDUSDOracle           = 0xa6310dE7b3B310404bd007e5AED7647C9aDA898C;
// address constant Mumbai_ChainLinkOracle        = 0xB548edFC1592d16520D76020FEAc95364A7e177d;
// address constant Mumbai_ChainLinkOracleGBP     = 0x3D2657603F37A15c26c62C403c6C61DA58f060B0;
// address constant Mumbai_FactoryV2              = 0x14AE79854B9b63F2c5e0Fd740fAd8282b91a217A;
// address constant Mumbai_FactoryProvider        = 0xc5B3419E3F26EffC87ffD25C3904c7b709D860b3;
// address constant Mumbai_CurrencyFeedV2         = 0xE2b23ACC8B25a90b0f7a16033B5a2495dfea338e;
// address constant Mumbai_GoldOracleTangibleV2   = 0x8502303CCB947176D1b5e1b8496483524Dcaef2c;
// address constant Mumbai_RealtyOracleTangibleV2 = 0x0852edA93D812f804652502bD181a75c0b2D6584;
// address constant Mumbai_TangibleV3TokenOracle  = 0x4D4932397F4D0508e709ADAd73292707c93F464c;
// address constant Mumbai_Exchange               = 0xC58439a5c23e41310a606a22cE72B79439Ac2c99;
// address constant Mumbai_SellFeeDistributorV2   = 0x1Ba8F132596dE707d0d69ec895C592734aF79ad4;
// address constant Mumbai_TnftDeployerV2         = 0x5b0fE44EAbC306CDe90dB0af60739D8123757ff4;
// address constant Mumbai_PriceManager           = 0xbF6a4d73662444b759CD8A30DD4Ded7165bd69b0;
// address constant Mumbai_RentManagerDeployer    = 0xe61be104CBaCC4876283041435D15f252003Fc96;
// address constant Mumbai_TNFTMetadata           = 0xAe296cA58E2e8f4EbddDAB31cCA9698E5473F294;
// address constant Mumbai_OnSaleTracker          = 0x8069F201d7Aaf31a9D77efBAffB6CB4d45b9F5a7;
// address constant Mumbai_Marketplace            = 0x622302D13bdA7dD331E28ea69a7974A4ad58DA92;
// address constant Mumbai_TangibleGoldBarsTnft   = 0x59efb756b01969Fb92f2C615894B8AD084a644E6;
// address constant Mumbai_TangibleREstateTnft    = 0x17c606257483B965Fa6a7bA4E570Ce17aDebdF4C;
// address constant Mumbai_TangibleProfile        = 0x6b24fd66fe7e4820a06fE8a748b2848d5715ba71;
// address constant Mumbai_TangibleReaderHelper   = 0xb2Cc97983a948f63872aD37784729902547Bf6f8;

// ~ Mumbai Deployment 3 ~

//address constant Mumbai_BalanceBatchReader     = 0x6A1467D4c8dDe056424d2221331886D71Fe8cBf0;
//address constant Mumbai_MockMatrix             = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
//address constant Mumbai_USDUSDOracle           = 0xa7be1e93dD69afF628f2033e7912C3c5b2aa8700;
//address constant Mumbai_ChainLinkOracle        = 0xB548edFC1592d16520D76020FEAc95364A7e177d;
//address constant Mumbai_ChainLinkOracleGBP     = 0xB7dFC1a5b7fE556990ba0321B7e7BCeE97341448;
//address constant Mumbai_FactoryV2              = 0x8ce33d2633cbdb326956aBAbDaEeBaC08527fcC9;
//address constant Mumbai_FactoryProvider        = 0xc5B3419E3F26EffC87ffD25C3904c7b709D860b3;
//address constant Mumbai_CurrencyFeedV2         = 0x50fB404F31872C2BC17395866eE8a7277Aff4d71;
//address constant Mumbai_GoldOracleTangibleV2   = 0x9a0855E5641f73e76127868e81293b223372DbE6;
//address constant Mumbai_RealtyOracleTangibleV2 = 0x1B0219f07a9a5744129f9AF85De8f7a24e0a971B;
//address constant Mumbai_TangibleV3TokenOracle  = 0x4D4932397F4D0508e709ADAd73292707c93F464c;
//address constant Mumbai_Exchange               = 0x6E8292c55C9439E8387428C5ed27289d18A9f565;
//address constant Mumbai_SellFeeDistributorV2   = 0x6889D63Cb73faB7d9Bf8Fc2600ee529C665979C9;
//address constant Mumbai_TnftDeployerV2         = 0x6A70BA0EAa837BD2fd75f369B60000bECAC7bAf8;
//address constant Mumbai_PriceManager           = 0xdC1906c73a9DBDf6220ce325706b0D0Ef027025B;
//address constant Mumbai_RentManagerDeployer    = 0x2198b45c98C7472159B19267Ef2b26aC6FAf28be;
//address constant Mumbai_TNFTMetadata           = 0x118C87b3623Dc69556b714C1E8C371853CdA49c8;
//address constant Mumbai_Marketplace            = 0x14D6d11Bf5CbA3E971faDb564270De148ACd2980;
//address constant Mumbai_TangibleGoldBarsTnft   = 0x18770d94eF20ec73c5e4a86B68E9812B8B7E32ae;
//address constant Mumbai_TangibleREstateTnft    = 0xBd8127866ccEbc73f1695470668fC92E3FAF1c23;
//address constant Mumbai_TangibleProfile        = 0x6b24fd66fe7e4820a06fE8a748b2848d5715ba71;
//address constant Mumbai_TangibleReaderHelper   = 0x9dd9C081C48578b3D983099051d5211a39055E49;

// ~ Mumbai Deployment 4 ~

// address constant Mumbai_BalanceBatchReader     = 0x6A1467D4c8dDe056424d2221331886D71Fe8cBf0;
// address constant Mumbai_MockMatrix             = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
// address constant Mumbai_USDUSDOracle           = 0xa7be1e93dD69afF628f2033e7912C3c5b2aa8700;
// address constant Mumbai_ChainLinkOracle        = 0xB548edFC1592d16520D76020FEAc95364A7e177d;
// address constant Mumbai_ChainLinkOracleGBP     = 0xB7dFC1a5b7fE556990ba0321B7e7BCeE97341448;
// address constant Mumbai_FactoryV2              = 0x748d79677e44Cd4692EB01953702C5aEc2D95687;
// address constant Mumbai_FactoryProvider        = 0xc5B3419E3F26EffC87ffD25C3904c7b709D860b3;
// address constant Mumbai_GoldOracleTangibleV2   = 0xd8c014F5d7280bee97C65f7fC3f9B73099286BAb;
// address constant Mumbai_RealtyOracleTangibleV2 = 0x639ca69fA81F8eb290f8212a5CA888C8383057FF;
// address constant Mumbai_TangibleV3TokenOracle  = 0x4D4932397F4D0508e709ADAd73292707c93F464c;
// address constant Mumbai_SellFeeDistributorV2   = 0x87134AB79C7E4c08a97Ddf8B6193640d1058E5a2;
// address constant Mumbai_TnftDeployerV2         = 0xaBb089F1D4d86b0f1FaaF797Fa6a5b8c6e222879;
// address constant Mumbai_PriceManager           = 0x62796A627eb70b344782C0c2744aDb1C96E59DCc;
// address constant Mumbai_RentManagerDeployer    = 0x3013A23b0Fe6Ea37554131b434D88E4e88e03EfF;
// address constant Mumbai_TNFTMetadata           = 0x621671133ceff74c1624A305b7cE7951847200ed;
// address constant Mumbai_OnSaleTracker          = 0x9C2860Bf4115B18aC9dd63aBAaaE32b7DE5462c4;
// address constant Mumbai_Marketplace            = 0x472De8B9C4203E5efEA94C2154B315edEfF55180;
// address constant Mumbai_TangibleGoldBarsTnft   = 0xe31c56BC4b018f612ecC1bBcc8610007a7Fa7170;
// address constant Mumbai_TangibleREstateTnft    = 0x357e328E00Df30D15fc0625D63dcb50D4734656E;
// address constant Mumbai_TangibleProfile        = 0x6b24fd66fe7e4820a06fE8a748b2848d5715ba71;
// address constant Mumbai_TangibleReaderHelper   = 0x7388DC9d3Ae359557350BCC52B6F4E80D0c9B34E;

// ~ Mumbai Deployment 5 ~

// address constant Mumbai_BalanceBatchReader     = 0x6A1467D4c8dDe056424d2221331886D71Fe8cBf0;
// address constant Mumbai_MockMatrix             = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
// address constant Mumbai_USDUSDOracle           = 0xa7be1e93dD69afF628f2033e7912C3c5b2aa8700;
// address constant Mumbai_ChainLinkOracle        = 0xB548edFC1592d16520D76020FEAc95364A7e177d;
// address constant Mumbai_ChainLinkOracleGBP     = 0xB7dFC1a5b7fE556990ba0321B7e7BCeE97341448;
// address constant Mumbai_FactoryV2              = 0x726B57922aF0417aB8665C7f69985C692a709CA7;
// address constant Mumbai_FactoryProvider        = 0xc5B3419E3F26EffC87ffD25C3904c7b709D860b3;
// address constant Mumbai_CurrencyFeedV2         = 0xBe3E6cfe13C74a780e7D73F684810319ed8C4746;
// address constant Mumbai_GoldOracleTangibleV2   = 0xd8c014F5d7280bee97C65f7fC3f9B73099286BAb;
// address constant Mumbai_RealtyOracleTangibleV2 = 0x639ca69fA81F8eb290f8212a5CA888C8383057FF;
// address constant Mumbai_TangibleV3TokenOracle  = 0x4D4932397F4D0508e709ADAd73292707c93F464c;
// address constant Mumbai_Exchange               = 0xf5E421e81081DBE4b64c20C2d5717C3CCfE01f19;
// address constant Mumbai_SellFeeDistributorV2   = 0x87134AB79C7E4c08a97Ddf8B6193640d1058E5a2;
// address constant Mumbai_TnftDeployerV2         = 0x50938f27c4DFCdFA4B760e8145502e039DF746e6;
// address constant Mumbai_PriceManager           = 0x62796A627eb70b344782C0c2744aDb1C96E59DCc;
// address constant Mumbai_RentManagerDeployer    = 0xC7001d6E3D8A683fD3b209F15E839634CA303c4A;
// address constant Mumbai_TNFTMetadata           = 0x621671133ceff74c1624A305b7cE7951847200ed;
// address constant Mumbai_Marketplace            = 0xe746832A02Bf411f646e84a753456f169b298a55;
// address constant Mumbai_TangibleGoldBarsTnft   = 0xc9DeCc70c86500A1E96B37aB167D4aE24894aC3D;
// address constant Mumbai_TangibleREstateTnft    = 0x033b8db13b062758E08A57e7A52e6B3363C680f7;
// address constant Mumbai_RentManagerTnft        = 0x0d09555530972535FdF1Ce55B63Ae3ca886A691e;
// address constant Mumbai_TangibleProfile        = 0x6b24fd66fe7e4820a06fE8a748b2848d5715ba71;
// address constant Mumbai_TangibleReaderHelper   = 0x7388DC9d3Ae359557350BCC52B6F4E80D0c9B34E;

// ~ Mumbai Deployment 6 ~

address constant Mumbai_BalanceBatchReader     = 0x6A1467D4c8dDe056424d2221331886D71Fe8cBf0;
address constant Mumbai_MockMatrix             = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
address constant Mumbai_USDUSDOracle           = 0xa7be1e93dD69afF628f2033e7912C3c5b2aa8700;
address constant Mumbai_ChainLinkOracle        = 0xB548edFC1592d16520D76020FEAc95364A7e177d;
address constant Mumbai_ChainLinkOracleGBP     = 0xB7dFC1a5b7fE556990ba0321B7e7BCeE97341448;
address constant Mumbai_FactoryV2              = 0x46d1e38044Db99fA8Cf7dB3a909E50095f525660;
address constant Mumbai_FactoryProvider        = 0xc5B3419E3F26EffC87ffD25C3904c7b709D860b3;
address constant Mumbai_CurrencyFeedV2         = 0xb806296C3f7dd6dB3bE298f0cD26CddFD69B6712;
address constant Mumbai_GoldOracleTangibleV2   = 0x8E58776Ef917bD76A18AC4aEC8b15FF1856F1e48;
address constant Mumbai_RealtyOracleTangibleV2 = 0x893b9F5C0C959EaA07656eeBA8191D86F1da4214;
address constant Mumbai_TangibleV3TokenOracle  = 0x4D4932397F4D0508e709ADAd73292707c93F464c;
address constant Mumbai_Exchange               = 0x256f9548A21A836A5d085A8373725367713676DA;
address constant Mumbai_SellFeeDistributorV2   = 0x1a00183EB2790965bBB422aE8c733b2aFCc567e6;
address constant Mumbai_TnftDeployerV2         = 0xDfa1D0ee4AEC912D060FD83E131b395376947Faf;
address constant Mumbai_PriceManager           = 0x9fAB2B7D6546F36D010128EAB84858FD53eA8E97;
address constant Mumbai_RentManagerDeployer    = 0x9D493c8A2d8750B741d77Ba39BC1965f0A2123b4;
address constant Mumbai_TNFTMetadata           = 0x5d6A1E3d2Da9302e155a1E283831521E36B3f001;
address constant Mumbai_OnSaleTracker          = 0x0495E64F77762078DB476A206c6b4Da996DCbf17;
address constant Mumbai_Marketplace            = 0xB4CdDEa1803f97CFDc6C1fa7d60762A242FA0848;
address constant Mumbai_TangibleGoldBarsTnft   = 0xf498e91D9837988894DC495fe35Ed24cd15e594B;
address constant Mumbai_TangibleREstateTnft    = 0x88C520817Bc6e6B2C825C1670ec7909B3c9097D0;
address constant Mumbai_RentManagerTnft        = 0x8B89772D4a63c994C88e717dbd8D69A3A21BA550;
address constant Mumbai_TangibleProfile        = 0x6b24fd66fe7e4820a06fE8a748b2848d5715ba71;
address constant Mumbai_TangibleReaderHelper   = 0x7F5D9EFbd298b8fb16967a9af9f38d41dddac943;