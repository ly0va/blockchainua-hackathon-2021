import { expect, use } from 'chai';
import '@nomiclabs/hardhat-ethers';
import * as hardhat from 'hardhat';
import { ethers } from 'ethers';
import { solidity } from 'ethereum-waffle';

use(solidity);

describe('Tests', () => {
    let owner: ethers.Signer;
    let address1: ethers.Signer;
    let address2: ethers.Signer;
    let usdt: ethers.Contract;
    let governance: ethers.Contract;
    let wusdt: ethers.Contract;

    before('deploy contracts', async () => {
        [owner, address1, address2] = await hardhat.ethers.getSigners();
        let factory = await hardhat.ethers.getContractFactory('TestUSDT');
        usdt = await factory.deploy();
        factory = await hardhat.ethers.getContractFactory('Governance');
        governance = await factory.connect(owner).deploy(await owner.getAddress());
        factory = await  hardhat.ethers.getContractFactory('wUSDT');
        wusdt = await factory.connect(owner).deploy(governance.address, usdt.address, 0);
        console.log(`Deployed success, address of wUSDT: ${wusdt.address}`)
    });

    it('deposit', async () => {
        await usdt.mint(await address1.getAddress(), 100000);
        await usdt.connect(address1).approve(wusdt.address, 100000);
        await wusdt.connect(address1).mint(await address1.getAddress(), 1000);
        expect(await wusdt.balanceOf(await address1.getAddress())).to.eq(1000);
    });

    it('simple transfer', async () => {
        let rec = await wusdt.connect(address1).transfer(await address2.getAddress(), 500);
        await rec.wait();
        expect(await wusdt.balanceOf(await address1.getAddress())).to.eq(500);
        expect(await wusdt.balanceOf(await address2.getAddress())).to.eq(500);
    });
});
