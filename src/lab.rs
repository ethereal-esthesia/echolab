use crate::machines::Machine;

pub struct Lab {
    title: String,
    machines: Vec<Machine>,
}

impl Lab {
    pub fn new(title: &str) -> Self {
        Self {
            title: title.to_owned(),
            machines: Vec::new(),
        }
    }

    pub fn with_machine(mut self, machine: Machine) -> Self {
        self.machines.push(machine);
        self
    }

    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn machines(&self) -> &[Machine] {
        self.machines.as_slice()
    }
}
