import { HardhatUserConfig } from "hardhat/config";

// PLUGINS
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-deploy";
import "solidity-coverage";
import "@nomicfoundation/hardhat-chai-matchers";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";

// Process Env Variables
import * as dotenv from "dotenv";
dotenv.config({ path: __dirname + "/.env" });
const ALCHEMY_ID = process.env.ALCHEMY_ID;

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: "",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/_5K15-wfBoWkGwdonG4o77iUgon8ut3N",
      },
    },
    mainnet: {
      accounts: process.env.PK ? [process.env.PK] : [],
      chainId: 1,
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_ID}`,
    },
    tenderly: {
      accounts: process.env.PK ? [process.env.PK] : [],
      url: "https://rpc.vnet.tenderly.co/devnet/sop-integration/a3cce0b2-7ec7-4ab7-b587-287ae7df97df",
    },
  },

  solidity: {
    compilers: [
      {
        version: "0.7.3",
        settings: {
          optimizer: { enabled: true, runs: 100 },
        },
      },
      {
        version: "0.8.4",
        settings: {
          optimizer: { enabled: true, runs: 100 },
        },
      },
    ],
  },
  external: {
    contracts: [
      {
        artifacts: "node_modules/@uniswap/v3-core/artifacts",
      },
      {
        artifacts: "node_modules/@uniswap/v3-periphery/artifacts",
      },
    ],
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
