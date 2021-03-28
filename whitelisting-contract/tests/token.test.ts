import { expect, use } from 'chai';
import '@nomiclabs/hardhat-ethers';
import * as hardhat from 'hardhat';
import { ethers, BigNumber } from 'ethers';
import { solidity } from 'ethereum-waffle';

use(solidity);

describe('Tests', () => {
    let deployer: ethers.Signer;
    let minter: ethers.Signer;
    let alice: ethers.Signer;
    let bob: ethers.Signer;
    let Zkam: ethers.Contract;

    before('deploy Zkam token contract', async () => {
        [deployer, minter, alice, bob] = await hardhat.ethers.getSigners();
        const factory = await hardhat.ethers.getContractFactory('ERC20Token');
        Zkam = await factory.connect(deployer).deploy(minter.getAddress(), minter.getAddress(), 0);
    });

    it('check initial balances', async () => {
        expect(await Zkam.balanceOf(minter.getAddress())).to.eq(BigNumber.from(10).pow(27));
        expect(await Zkam.balanceOf(alice.getAddress())).to.eq(BigNumber.from(0));
        expect(await Zkam.balanceOf(bob.getAddress())).to.eq(BigNumber.from(0));
    });

    it('nested delegation', async () => {
        await Zkam.connect(minter).transfer(alice.getAddress(), BigNumber.from(10).pow(18));
        await Zkam.connect(minter).transfer(bob.getAddress(), BigNumber.from(10).pow(18));
    
        let currectVotes0 = await Zkam.getCurrentVotes(alice.getAddress());
        let currectVotes1 = await Zkam.getCurrentVotes(bob.getAddress());
        expect(currectVotes0).to.be.eq(0);
        expect(currectVotes1).to.be.eq(0);
    
        await Zkam.connect(alice).delegate(bob.getAddress());
        currectVotes1 = await Zkam.getCurrentVotes(bob.getAddress());
        expect(currectVotes1).to.be.eq(BigNumber.from(10).pow(18));
    
        await Zkam.connect(bob).delegate(bob.getAddress());
        currectVotes1 = await Zkam.getCurrentVotes(bob.getAddress());
        expect(currectVotes1).to.be.eq(BigNumber.from(10).pow(18).mul(2));
      })
});
