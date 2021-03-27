import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-solpp';

const config = { 

};

export default {
    solidity: {
        version: '0.7.6',
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
