use echo_lab::lab::Lab;
use echo_lab::machines::iie;

fn main() {
    let lab = Lab::new("Echo Lab").with_machine(iie::apple_iie());

    println!("{}", lab.title());
    println!("Machines in lab:");

    for (index, machine) in lab.machines().iter().enumerate() {
        println!("{}. {}", index + 1, machine.name);
        println!("   {}", machine.description);
    }
}
