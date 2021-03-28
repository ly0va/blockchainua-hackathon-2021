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

        await governance.connect(owner).setOperatorStatus(owner.getAddress(), 1);

        console.log(`Deployed success, address of wUSDT: ${wusdt.address}`)
    });

    it('deposit', async () => {
        await usdt.mint(await address1.getAddress(), 100000);
        await usdt.connect(address1).approve(wusdt.address, 100000);
        await wusdt.connect(address1).mint(address1.getAddress(), 1000);
        expect(await wusdt.balanceOf(address1.getAddress())).to.eq(1000);
    });

    it('simple transfer', async () => {
        let rec = await wusdt.connect(address1).transfer(await address2.getAddress(), 500);
        await rec.wait();
        expect(await wusdt.balanceOf(address1.getAddress())).to.eq(500);
        expect(await wusdt.balanceOf(address2.getAddress())).to.eq(500);
    });

    it('prove block', async() => {
        const transaction1 =
            (await address1.getAddress()).substr(2,40).padStart(64,'0')
            + (await address2.getAddress()).substr(2,40).padStart(64,'0')
            + "10".padStart(64, '0')
            + "2".padStart(64, '0');

        const transaction2 =
            (await address2.getAddress()).substr(2,40).padStart(64,'0')
            + (await address1.getAddress()).substr(2,40).padStart(64,'0')
            + "20".padStart(64, '0')
            + "3".padStart(64, '0');

        const transactionData = ethers.utils.arrayify('0x' + transaction1 + transaction2);
        await wusdt.connect(owner).proveBlock(1,
            owner.getAddress(),
            Date.now(),
            transactionData,
            ethers.utils.arrayify('0x0101')
        );

        expect(await wusdt.balanceOf(address1.getAddress())).to.eq(514);
        expect(await wusdt.balanceOf(address2.getAddress())).to.eq(481);
        expect(await wusdt.balanceOf(owner.getAddress())).to.eq(5);
    })
});
