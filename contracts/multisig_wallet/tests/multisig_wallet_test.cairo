use core::array::{Array, ArrayTrait, SpanTrait};
use core::serde::Serde;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
};
use starknet::ContractAddress;
use openzeppelin_governance::multisig::interface::{
    IMultisigDispatcher, IMultisigDispatcherTrait, TransactionState,
};

#[starknet::interface]
trait IExampleCounter<TState> {
    fn get(self: @TState) -> u32;
    fn increment(ref self: TState) -> u32;
}

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

fn deploy_counter(initial: u32) -> IExampleCounterDispatcher {
    let class = declare("ExampleCounter").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    initial.serialize(ref calldata);
    let (address, _) = class.deploy(@calldata).unwrap();
    IExampleCounterDispatcher { contract_address: address }
}

fn deploy_multisig(signers: Array<ContractAddress>, quorum: u32) -> IMultisigDispatcher {
    let class = declare("MultisigWallet").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    quorum.serialize(ref calldata);
    signers.serialize(ref calldata);
    let (address, _) = class.deploy(@calldata).unwrap();
    IMultisigDispatcher { contract_address: address }
}

fn assert_signers_eq(actual: Span<ContractAddress>, expected: @Array<ContractAddress>) {
    assert(actual.len() == expected.len(), 'signers len mismatch');
    let mut i: usize = 0_usize;
    while i < actual.len() {
        assert(*actual.at(i) == *expected.at(i), 'signer mismatch');
        i += 1_usize;
    }
}

#[test]
fn test_constructor_sets_quorum_and_signers() {
    let signer_a = addr(0x1111);
    let signer_b = addr(0x2222);
    let signers = array![signer_a, signer_b];
    let quorum = 2_u32;

    let multisig = deploy_multisig(signers.clone(), quorum);

    assert(multisig.get_quorum() == quorum, 'quorum mismatch');
    let onchain_signers = multisig.get_signers();
    assert_signers_eq(onchain_signers, @signers);
}

#[test]
fn test_submit_does_not_auto_confirm() {
    let signer_a = addr(0x1111);
    let signer_b = addr(0x2222);
    let signers = array![signer_a, signer_b];
    let quorum = 2_u32;

    let multisig = deploy_multisig(signers, quorum);
    let counter = deploy_counter(0);

    let calldata: Array<felt252> = array![];
    let salt: felt252 = 0;
    start_cheat_caller_address(multisig.contract_address, signer_a);
    let tx_id = multisig.submit_transaction(
        counter.contract_address,
        selector!("increment"),
        calldata.span(),
        salt,
    );

    let confirmations = multisig.get_transaction_confirmations(tx_id);
    assert(confirmations == 0, 'submit auto-confirmed');
}

#[test]
fn test_submit_confirm_execute_happy_path() {
    let signer_a = addr(0x1111);
    let signer_b = addr(0x2222);
    let signers = array![signer_a, signer_b];
    let quorum = 2_u32;

    let multisig = deploy_multisig(signers, quorum);
    let counter = deploy_counter(0);

    let calldata: Array<felt252> = array![];
    let salt: felt252 = 0;

    start_cheat_caller_address(multisig.contract_address, signer_a);
    let tx_id = multisig.submit_transaction(
        counter.contract_address,
        selector!("increment"),
        calldata.span(),
        salt,
    );

    multisig.confirm_transaction(tx_id);

    start_cheat_caller_address(multisig.contract_address, signer_b);
    multisig.confirm_transaction(tx_id);

    start_cheat_caller_address(multisig.contract_address, signer_a);
    multisig.execute_transaction(
        counter.contract_address,
        selector!("increment"),
        calldata.span(),
        salt,
    );

    assert(multisig.get_transaction_state(tx_id) == TransactionState::Executed, 'tx not executed');
    assert(counter.get() == 1, 'counter not incremented');
}

#[test]
#[should_panic(expected: 'Multisig: not a signer')]
fn test_non_signer_cannot_submit() {
    let signer_a = addr(0x1111);
    let signer_b = addr(0x2222);
    let signers = array![signer_a, signer_b];
    let quorum = 2_u32;

    let multisig = deploy_multisig(signers, quorum);
    let counter = deploy_counter(0);

    let calldata: Array<felt252> = array![];
    let salt: felt252 = 0;
    let outsider = addr(0x9999);

    start_cheat_caller_address(multisig.contract_address, outsider);
    multisig.submit_transaction(
        counter.contract_address,
        selector!("increment"),
        calldata.span(),
        salt,
    );
}

#[test]
#[should_panic(expected: 'Multisig: unauthorized')]
fn test_admin_ops_self_only() {
    let signer_a = addr(0x1111);
    let signer_b = addr(0x2222);
    let signers = array![signer_a, signer_b];
    let quorum = 2_u32;

    let multisig = deploy_multisig(signers, quorum);
    let new_signer = addr(0x3333);

    start_cheat_caller_address(multisig.contract_address, signer_a);
    multisig.add_signers(2, array![new_signer].span());
}
