import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-solpp';
import { config as dotenvConfig } from "dotenv";
import { resolve } from 'path';

dotenvConfig({ path: resolve(__dirname, "./.env") });

const config = {
};

export default {
    solidity: {
        version: '0.7.0',
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
