# Baskets

## What are Baskets?

Baskets are Elastic Erc20 contracts that allow TNFT owners to deposit their TNFTs in and receive Basket Erc20 tokens in return. Each basket that is created/deployed will only support a specified category of TNFTs. For example if a basket contract is created to support Real Estate TNFTs, only TNFTs of that category can be deposited into that Basket. 

The value of the Erc20 token is determined by the total value of the TNFTs in the basket, as well as any rent that is accrued by the basket.

The Tangible Real Estate TNFT Baskets will provide a more liquid and accessible way for users to invest in real estate NFTs. By creating an Erc20 token that represents a basket of NFTs, users can easily deposit and redeem their investments. The development of a robust oracle and fee collection mechanism will ensure the long-term sustainability of the platform.

## Contracts

- [Basket](./src/Baskets.sol) - The Erc20 contract that facilitates the transaction of Basket tokens and TNFTs. Are able to be created by anyone who holds a TNFT.
- [BasketDeployer](./src/BasketsDeployer.sol) - This contract allows the Tangible Factory to create new Basket contracts.

## Tests

- [MumbaiBasketsTest](./src/Baskets.t.sol) - This test file contains numerous integration unit tests on the Mumbai testnet. References the underlying Tangible core contracts that live on Mumbai.
- [BasketsManagerTest](./src/BasketsManager.t.sol) - This test file contains integration testing for the BasketsManager smart contract.
- [StressTests](./src/BasketsStressTests.t.sol) - This test file contains stress tests created using Foundry's advanced testing tools. This is to expose the limitations of the Basket contract.

## Testing

This testing and development framework uses [foundry](https://book.getfoundry.sh/), a smart contract development toolchain that manages your dependencies, compiles your project, runs tests, deploys, and lets you interact with the chain from the command-line and via Solidity scripts.

To run integration tests using forge:
`forge test` 

Ensure you have a mumbai rpc url assigned to env variable called `MUMBAI_RPC_URL`
