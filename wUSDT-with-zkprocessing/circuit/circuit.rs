// This is pseudocode only


pub struct CircuitSignature<E: RescueEngine + JubjubEngine> {
    /// TODO :)
}

pub struct CircuitTransaction<E: RescueEngine + JubjubEngine> {
    pub from: Option<E::Fr>,
    pub to: Option<E::Fr>,
    pub amount: Option<E::Fr>,
    pub fee: Option<E::Fr>,
    pub nonce: Option<E::Fr>,
    pub valid_from: Option<E::Fr>,
    pub valid_until: Option<E::Fr>,

    pub signature: CircuitSignature<E>,
}

pub struct TransactionsBlockCircuit<'a, E: RescueEngine + JubjubEngine> {
    pub commitment: Option<E::Fr>,

    pub old_storage_root: Option<E::Fr>,
    pub fee_address: Option<E::Fr>,
    pub block_timestamp: Option<E::Fr>,

    pub transactions: Vec<CircuitTransaction<E>>,
    pub storage_audit_paths: Vec<Vec<Option<E::Fr>>>,
}

impl<'a, E: RescueEngine + JubjubEngine> Circuit<E> for TransactionsBlockCircuit<'a, E> {
    fn synthesize<CS: ConstraintSystem<E>>(self, cs: &mut CS) -> Result<(), SynthesisError> {
        let commitment =
            AllocatedNum::alloc(cs.namespace(|| "commitment"), || {
                self.commitment.grab()
            })?;
        commitment.inputize(cs.namespace(|| "inputize commitment"))?;

        let start_storage_root = AllocatedNum::alloc(cs, old_storage_root);
        let fee_address = AllocatedNum::alloc(cs, fee_address);
        let block_timestamp = AllocatedNum::alloc(cs, block_timestamp);

        let mut onchain_data = Vec::new();
        let mut cur_root_hash = start_storage_root;

        for (tx, storage_audit_path) in self.transactions.zip(storage_audit_paths) {
            self.process_transaction(
                &mut onchain_data,
                &mut cur_root_hash,
                tx,
                &block_timestamp,
                storage_audit,
            );
        }

        let final_storage_root = cur_root_hash;

        {
            let mut initial_hash_data: Vec<Boolean> = vec![];

            initial_hash_data.extend(old_storage_root.into_padded_be_bits(256));

            initial_hash_data.extend(final_storage_root.into_padded_be_bits(256));

            assert_eq!(initial_hash_data.len(), 512);

            let mut hash_block = sha256::sha256(
                cs.namespace(|| "initial rolling sha256"),
                &initial_hash_data,
            )?;

            let mut pack_bits = vec![];
            pack_bits.extend(hash_block);
            pack_bits.extend(fee_address.into_padded_be_bits(256));
            assert_eq!(pack_bits.len(), 512);

            hash_block = sha256::sha256(cs.namespace(|| "hash with fee address"), &pack_bits)?;

            let mut pack_bits = vec![];
            pack_bits.extend(hash_block);
            pack_bits.extend(block_timestamp.into_padded_be_bits(256));

            hash_block = sha256::sha256(cs.namespace(|| "hash with block timestamp"), &pack_bits)?;

            let mut pack_bits = vec![];
            pack_bits.extend(hash_block);
            pack_bits.extend(onchain_data.into_iter());

            hash_block = sha256::sha256(cs.namespace(|| "final hash with onchain data"), &pack_bits)?;

            hash_block.reverse();
            hash_block.truncate(E::Fr::CAPACITY as usize);

            let final_hash =
                pack_bits_to_element_strict(cs.namespace(|| "final_hash"), &hash_block)?;
            cs.enforce(
                || "enforce external data hash equality",
                |lc| lc + commitment.get_variable(),
                |lc| lc + CS::one(),
                |lc| lc + final_hash.get_variable(),
            );
        }
        Ok(())
    }
}

impl<'a, E: RescueEngine + JubjubEngine> TransactionsBlockCircuit<'a, E> {
    fn prove_storage_filling_slot<CS: ConstraintSystem<E>>(
        &self,
        root_hash: &mut AllocatedNum<E>,
        storage_audit_path: &Vec<Option<E::Fr>>,
    ) -> Result<(), SynthesisError> {
        /// TODO :)
        Ok(())
    }

    fn check_user_signature<CS: ConstraintSystem<E>>(
        &self,
        message: &Vec<Boolean>,
        signature: &CircuitSignature<E>,
        signer: &AllocatedNum<E>,
    ) -> Result<(), SynthesisError> {
        /// TODO :)
        Ok(())
    }

    fn validate_tx_timestamp<CS: ConstraintSystem<E>>(
        &self,
        valid_from: &AllocatedNum<E>,
        block_timestamp: &AllocatedNum<E>,
        valid_until: &AllocatedNum<E>,
    ) -> Result<(), SynthesisError> {
        circuit_untils::enforce_lt(valid_from, block_timestamp)?;
        circuit_untils::enforce_lt(block_timestamp, valid_until)?;
        Ok(())
    }

    fn process_transaction<CS: ConstraintSystem<E>>(
        &self,
        onchain_data: &mut Vec<Boolean>,
        root_hash: &mut AllocatedNum<E>,
        tx: &CircuitTransaction<E>,
        block_timestamp: &AllocatedNum<E>,
        storage_audit_path: &Vec<Option<E::Fr>>,
    ) -> Result<(), SynthesisError> {
        let from = AllocatedNum::alloc(tx.from);
        let to = AllocatedNum::alloc(tx.to);
        let amount = AllocatedNum::alloc(tx.amount);
        let fee = AllocatedNum::alloc(tx.fee);
        let nonce = AllocatedNum::alloc(tx.nonce);

        let valid_from = AllocatedNum::alloc(tx.valid_from);
        let valid_until = AllocatedNum::alloc(tx.valid_until);

        let mut to_check_signature_message = Vec::new();
        to_check_signature_message.extend(from.into_padded_be_bits(256));
        to_check_signature_message.extend(to.into_padded_be_bits(256));
        to_check_signature_message.extend(amount.into_padded_be_bits(256));
        to_check_signature_message.extend(fee.into_padded_be_bits(256));
        to_check_signature_message.extend(nonce.into_padded_be_bits(256));
        to_check_signature_message.extend(valid_from.into_padded_be_bits(256));
        to_check_signature_message.extend(valid_until.into_padded_be_bits(256));

        self.check_user_signature(
            cs,
            to_check_signature,
            tx.signature,
            &from
        )?;

        self.prove_storage_filling_slot(
            cs,
            root_hash,
            storage_audit_path
        )?;

        self.validate_tx_timestamp(
            cs,
            &valid_from,
            block_timestamp,
            &valid_until
        );

        onchain_data.extend(from.into_padded_be_bits(256));
        onchain_data.extend(to.into_padded_be_bits(256));
        onchain_data.extend(amount.into_padded_be_bits(256));
        onchain_data.extend(fee.into_padded_be_bits(256));
        onchain_data.extend(nonce.into_padded_be_bits(256));

        Ok(())
    }
}
