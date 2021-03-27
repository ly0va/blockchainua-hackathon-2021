import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-solpp';
import { config as dotenvConfig } from "dotenv";
import { resolve } from 'path';

dotenvConfig({ path: resolve(__dirname, "./.env") });

const config = { 
    TOKEN_MINIMUM_TIME_BETWEEN_MINTS: process.env.TOKEN_MINIMUM_TIME_BETWEEN_MINTS
};

export default {
    solidity: {
        version: '0.8.0',
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    contractSizer: {
        runOnCompile: false
    },
    paths: {
        sources: './contracts'
    },
    solpp: {
        defs: config
    },
    networks: {
        hardhat: { },
    },
};
