#[starknet::contract]
mod ExampleCounter {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        value: u32,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ValueChanged: ValueChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct ValueChanged {
        value: u32,
        caller: starknet::ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial: u32) {
        self.value.write(initial);
    }

    #[external(v0)]
    fn get(self: @ContractState) -> u32 {
        self.value.read()
    }

    #[external(v0)]
    fn increment(ref self: ContractState) -> u32 {
        let next = self.value.read() + 1;
        self.value.write(next);
        let caller = starknet::get_caller_address();
        self.emit(Event::ValueChanged(ValueChanged { value: next, caller }));
        next
    }

    #[external(v0)]
    fn set(ref self: ContractState, value: u32) {
        self.value.write(value);
        let caller = starknet::get_caller_address();
        self.emit(Event::ValueChanged(ValueChanged { value, caller }));
    }
}
