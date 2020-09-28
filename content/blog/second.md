+++
title = "TicTacToe in Valerie"
date = 2020-09-29
description = "Baseline implementation using today's Valerie"
+++

This article will introduce the application model and make it work without a vDOM, using only component local 
state and the [valerie](https://crates.io/crates/valerie) framework. This is the second in a series 
[which starts here](@/blog/first.md).

The code for this example is here: [valerie/tree/state-feature/examples/tictactoe](https://github.com/emmanuelantony2000/valerie/tree/67668152ba4d8fe7f8c30aec4214f4c33d5e1486/examples/tictactoe)

# Valerie under the hood

Valerie defines a ```Node``` struct which implements a tree of references to DOM elements, augmented with the
additional information needed for owned attributes and callbacks. 

The philosophy is all ```Arc<Mutex<...>>``` all the time which is great for threading but, I suspect, needs some 
serious thinking and testing to ensure that there aren't latent data races waiting in hiding. This work may have 
been done.

Events are communicated using channels provided by the 
[```futures_intrusive``` crate](https://crates.io/crates/futures-intrusive). This crate is sophisticated and 
complete, ```lock_api``` aware, and valerie mostly makes use of one key part: ```state_broadcast_channel```.
 
There is a simple DOM builder macro - no RSX yet.

# Setting up a game

This sets up the main DOM and parallel data structure and inserts it into the ```body``` element. 
 
```rust
#[valerie(start)]
pub fn run() {
    App::render_single(game());
}

fn game() -> Node {
    div!(
        div!(
            board()
        ).class("game-board"),
        div!(
            div!(),
            ol!()
        ).class("game-info")
    ).class("game").into()
}
```

The most important function call is to ```board()``` and the rest of the divs just mirror the React tutorial 
structure, but aren't used.

# Board with component local state

Valerie uses a bundle of ```State*``` structs which are mutable and, in turn, propagate their changes through 
channels.

We can use generics to pass specific types through these channels. The specific types are the Model of our 
application, playing to Rust's strength as a strongly-typed language.

The game board is an array of nine squares which can be in one of a defined set of states, modelled as an 
enumerated type called  ```Square```.

```rust
#[derive(Copy, Clone, PartialEq)]
enum Square {
    Empty,
    X,
    O,
}

fn board() -> Node {
    let squares: [StateAtomic<Square>; 9] = [
        // Can't use array init shorthand because StateAtomic is not Copy
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
        StateAtomic::new(Square::Empty),
    ];
```

We need some other state to manage the game - whether the game is being played or has been won, and the player 
whose turn is next.

```rust
    let status = StateAtomic::new(Status::Playing);
    let next_player = StateAtomic::new(Square::X);
```

```Status``` is another simple enum.
 
```rust
#[derive(Copy, Clone, PartialEq)]
enum Status {
    Playing,
    Won,
}
```

Each square will spawn an instance of an async function which will listen for clicks on the receiver end of its 
channel. We also pass clones of the game state so that the function can control the game.

```rust
    for square in &squares {
        execute(turn_checker(squares.to_vec(), square.rx(), next_player.clone(), status.clone()));
    }
```

The DOM for the board is straight-forward. The ```status``` and ```next_player``` can be displayed by simply 
cloning the ```StateAtomic``` instance inline into the DOM. Changes through the transmitter are applied to the
DOM element automatically. The DOM for each square is delegated to a square function.

```rust
    div!(
        div!(
            status.clone(),
            next_player.clone()
        ).class("status"),
        div!(
            square(squares[0].clone(), status.clone(), next_player.clone()),
            square(squares[1].clone(), status.clone(), next_player.clone()),
            square(squares[2].clone(), status.clone(), next_player.clone())
        ).class("board-row"),
        div!(
            square(squares[3].clone(), status.clone(), next_player.clone()),
            square(squares[4].clone(), status.clone(), next_player.clone()),
            square(squares[5].clone(), status.clone(), next_player.clone())
        ).class("board-row"),
        div!(
            square(squares[6].clone(), status.clone(), next_player.clone()),
            square(squares[7].clone(), status.clone(), next_player.clone()),
            square(squares[8].clone(), status.clone(), next_player.clone())
        ).class("board-row")
    ).into()
```

The square is simple - each is a button of class ```"square"```. When clicked, a closure runs which changes 
the squares's state if the square is empty and the game is still being played. We just read the clones of the 
```StateAtomics``` with ```value()```. Changing the square's state with ```put(...)``` will send the value to 
the ```StateAtomic``` and all the cloned receivers, including the one we passed to the turn_checker.
   
```rust
fn square(state: StateAtomic<Square>, status: StateAtomic<Status>, next_player: StateAtomic<Square>) -> Node {
    button!(state.clone())
        .class("square")
        .on_event("click", (), move |_, _| {
            if status.value() == Status::Playing && state.value() == Square::Empty {
                state.put(next_player.value());
            }
        })
        .into()
}
```

Types can be rendered into the HTML element if they implement ```Display```. Since the next player is not rotated
when we win, we just change the prompt to show the next player or who won (ok ok).

```rust
impl Display for Square {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result {
        let s = match self {
            Square::Empty => "",
            Square::X => "X",
            Square::O => "O",
        };
        write!(f, "{}", s)
    }
}

impl Display for Status {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result {
        let s = match self {
            Status::Playing => "Next player: ",
            Status::Won => "Winner: ",
        };
        write!(f, "{}", s)
    }
}
```

This wraps up the DOM setup.

# The turn checker

This is the turn checker. It is an async function which sets up a loop to process each change to a square. 
We check if there are any complete lines in the clone of the full board sent to the function, and either set 
the winner, or flip the next player using rotate.

```rust
async fn turn_checker(squares: Vec<StateAtomic<Square>>, rx: StateReceiver<Channel>, next_player: StateAtomic<Square>, status: StateAtomic<Status>) {

    fn calculate_winner(squares: &Vec<Square>) -> bool {
        const LINES: [[usize; 3]; 8] = [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7, 8],
            [0, 3, 6],
            [1, 4, 7],
            [2, 5, 8],
            [0, 4, 8],
            [2, 4, 6],
        ];
        for [a, b, c] in &LINES {
            let a = squares[*a];
            let b = squares[*b];
            let c = squares[*c];
            if a != Square::Empty && a == b && a == c {
                return true;
            }
        }
        return false;
    }

    let mut old = StateId::new();
    while let Some((new, _)) = rx.receive(old).await {
        let squares: Vec<Square> = squares.iter().map(|s| s.value()).collect();
        if calculate_winner(&squares) {
            status.put(Status::Won);
        } else {
            next_player.put(next_player.value().rotate());
        }
        old = new;
    }
}

impl Square {
    pub fn rotate(self) -> Self {
        match self {
            Square::X => Square::O,
            Square::O => Square::X,
            _ => self
        }
    }
}
```

Valerie does afford us the opportunity to stratify the app according to Model/Model-View/View lines.

# What is happening here?

Each instance of ```board()``` is using something akin to component local state to create ```Arc<Mutex<...>>``` 
objects which are owned by the main loop ```Node``` tree. These objects are connected by associated channel 
end-points which can be transmitted through during DOM events. An async function can monitor receiver end-points 
to take higher-level actions.

More importantly though, we are passing around a domain model tightly-defined with Rust ```enums``` and 
```impl``` functions.

We have moved the React tutorial away from a stringly-typed model, significantly improving reliability and
maintainability.

# Next

Next we are going to look at what it might be like to lift the component-local state in ```StateAtomic``` up to App State,
and start to see shared data views and the foundations of a back-end.