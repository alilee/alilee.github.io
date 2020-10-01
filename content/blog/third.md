+++
title = "Borrowing from Fulcro for your Rust WASM SPA"
date = 2020-09-30
description = "A Fulcro-style normalised database over Valerie"
+++

This article will discuss app state and show one approach to it in Rust, continuing the TicTacToe application 
example and using the [valerie](https://crates.io/crates/valerie) framework. This is the third in a series 
[which starts here](@/blog/first.md) and continues from [where we left off last time](@/blog/second.md).

The code for this example is here: [my fork of valerie/examples/tictactoe](https://github.com/alilee/valerie/tree/cb8aa9f3de2caf3f46b0f31a2200c377086683e5/examples/tictactoe). 
(Actually this commit is a little ahead of this article) 

# Why you might want to lift state out of components

[Fulcro](http://book.fulcrologic.com) made this clear to me.

When one object appears at multiple locations in a page, the information needs to be stored at a 
top-level component and passed down (as props in React and clones of the ```State``` structs in valerie). This 
couples components and their nesting, to thread the state object from where it is stored, to where it is displayed.

When a deep sub-component references a piece of state, this must be known to each wrapping component.

For example, a nested view of order lines needs to make a decision about how to present information about the 
product it relates to. The order line state may know just the foreign key identifier of the product the line 
relates to, but the user may be expecting its short code, display name and packaging dimensions. It would be 
better if the decision about what to display could be delegated to the order line view, without asking order 
to pass down too much (any?) product information (and then, what if we want to join to stock on hand?).

Returning to our implementation of Tic Tac Toe, if our game was constructed like this:

```rust
fn game() -> Node {
    div!(
        div!(
            board(),  // NOTE: three boards!
            board(), 
            board(),
        ).class("game-board"),
        div!(
            div!(),
            ol!()
        ).class("game-info")
    ).class("game").into()
}
```

we would have had three independent games proceeding in parallel. 

A different intention would be for each of those boards to reference the same playing state - various 
views of the same data, remaining synchronised. Various view functions could show different perspectives 
on the running game. We could answer questions and put that information anywhere on the page, for example: 
how many turns done? Win possible next turn? How many doubles?

(Later we will explore how to select which intention is rendered.)

If we have our state completely separate from views, how would it look?

# Static-scope state we might call "Store"

In Rust, static-scoped items are accessible from any part of the application without being passed as 
parameters. What if the rest of state was accessible through a lookup to static stores, using an identifier?

The Store will be a generic dictionary (HashMap) which maps the identifier to a tuple of the target struct, 
and both sides of the channel we need to link up views to the object, and take action upon events. It will
be implemented through a trait:

```rust
pub trait Relation<K: Copy + Eq + Hash, V: Clone + Default + Send> {
    fn get(id: K) -> V;
    fn insert(id: K, value: V);
    fn mutate(id: K, m: &impl Mutator<V>);
    fn subscribe(id: K) -> StateReceiver<V>;
    fn notify(id: K);
}
```

Implementing ```Relation<K, V>``` for ```V``` means that associated functions of ```V``` can be used to interact
with uniquely identified instances of V - from anywhere in the DOM.

Mutations are a helper type that represent updates/changes to the struct as their own distinct struct. Even though 
it seems like unnecessary complexity, let this ride for a moment because it will become very useful when we want 
to pass those mutations to a remote back-end API, over the network.

Mutations just need to know how to apply themselves to their target type, producing a modified instance:

```rust
trait Mutator<V> {
    fn mutate(&self, v: &V) -> V;
}
```  

An illustrative example of implementing ```Relation```:

```rust
struct PostID(u32);

struct Post {
    id: PostID,
    body: String,
    author: String,
}

impl Relation<PostID, Post> for Post {
    // we need this impl to be easy...
}

// usage example:
let post = Post { 
    id: PostID(34), 
    body, 
    author, 
};
Post::insert(post.id, post);
let post = Post::get(PostID(34));
```

The branch in valerie (linked above), provides a macro implementation for such a dictionary (implemented using 
a HashMap). Let's have a look what that means for the TicTacToe code.

# Abstracting the Model

Firstly, we can abstract the Model. We can use some very simple and explicit structs.

A square is marked either empty, X or O, and starts out empty.

```rust
enum SquareMark {
    Empty,
    X,
    O,
}

impl Default for SquareMark {
    fn default() -> Self {
        Self::Empty
    }
}
``` 

We also use the mark to track which player is next (okok), so it needs a mutation which sets the starting player
and changes between players.

```rust
enum NextPlayerChange {
    Start,
    Next,
}

impl Mutator<SquareMark> for NextPlayerChange {
    fn mutate(&self, v: &SquareMark) -> SquareMark {
        use SquareMark::*;
        match self {
            Self::Start => X,
            Self::Next => match v {
                X => O,
                O => X,
                Empty => unreachable!(),
            },
        }
    }
}
```

A square is state, indexable within the board. We set up some defaults so they start Empty, but I've omitted 
this code.

```rust
struct SquareID(u8);

struct Square {
    id: SquareID,
    pub mark: SquareMark,
}
```

Squares change when they are clicked, but the change depends on the player, so that is a parameter of the mutator.

```rust
enum SquareChange {
    Mark(SquareMark),
}

impl Mutator<Arc<Square>> for SquareChange {
    fn mutate(&self, v: &Arc<Square>) -> Arc<Square> {
        let mut v: Square = Square::clone(v);
        match self {
            Self::Mark(mark) => v.mark = *mark,
        }
        Arc::new(v)
    }
}
```

You will notice that we are mutating ```Arc<Square>```, not ```Square```. We pass data around a lot through channels,
so our types need to be ```Clone```.

The board is interesting. Instead of an array of marks, we have an array of identifiers. The Squares themselves 
are managed by their own relation, so we reference into that. Board no longer knows what constitutes a Square.

The default board sets up references to nine new squares, which in turn, default to Empty. We also factor out 
our game logic for determining if the board contains any lines of three identical non-Empty marks.

```rust
struct Board {
    pub squares: [SquareID; 9],
}

impl Default for Board {
    fn default() -> Self {
        let mut squares = [SquareID(0); 9];
        for i in 0usize..9 {
            let square = Square::new(SquareID(i as u8));
            Square::new(square.id);
            squares[i] = square.id;
        }
        Self { squares }
    }
}

impl Board {
    pub fn calculate_winner(&self) -> bool {
        // ...
    }
}
```  

Game status has a very similar implementation to Square, and the mutator is the simplest setter, so not shown here.

Hopefully at this point you agree we have a model for playing a game of tictactoe, which is very much decoupled from 
the view.

I have not shown the implementations of the ```trait Relation``` yet. The code branch has two macros which implement 
the associated functions using a HashMap. All that is required to set up the Stores is:

```rust
// Square::get(SquareID) -> Arc<Square>
relation!(Square, SquareID, Arc<Square>);

// GameBoard::get() -> Arc<Board>
singleton!(GameBoard, Arc<Board>);
singleton!(GameStatus, Status);
singleton!(NextPlayer, SquareMark);
``` 

```singleton!``` is very similar to ```relation!``` and sets up reactive state which is not indexed by an identifier.

We can represent our game state! What does it do for our view?

# A clean view without model implementation noise

It's time to get paid. But first, there is one part of the ```trait Relation``` I hid from you. ```formatted``` 
will take the instance and pass the changed object from the receiver channel to a closure which generates the 
```Node``` text, which is inserted as the update.

```rust
fn game() -> Node {
    NextPlayer::mutate(NextPlayerChange::Start);
    execute(GameBoard::turn_checker());
    div!(div!(
        div!(
            GameStatus::formatted(move |s| {
                let s = match s {
                    Status::Playing => "Next player: ",
                    Status::Won => "Winner: ",
                };
                format!("{}", s)
            }),
            NextPlayer::formatted(move |p| {
                format!("{}", p)
            })
        )
        .class("status"),
        GameBoard::node()
    )
    .class("game-board"))
    .class("game")
    .into()
}
```

```NextPlayer``` needed to be mutated because it is a singleton ```SquareMark``` and they default to 
Empty, remember?

```game()``` executes an event-triggered function turn-checker, which we'll return to in a moment.

The game status is used to generate the label text, and the next player is used to display the mark of the next 
player. Finally, we insert the board as a node, which is a function we need to write, and we do it by re-opening 
the struct. It just loops through the squares in rows of three, and inserts three of the nodes created by 
```square()```.

Notice that we are only passing the identifier of the square.

```rust
impl GameBoard {
    pub fn node() -> Node {
        let board = Self::get();
        let board = &board.squares;
        let mut parent = div!();
        for row in board.chunks(3) {
            let mut row_div: Tag<html::elements::Div> = div!().class("board-row");
            for id in row {
                row_div = row_div.push(square(*id));
            }
            parent = parent.push(row_div);
        }
        parent.into()
    }

    pub async fn turn_checker() {
        let rx = Self::subscribe();
        let mut old = StateId::new();
        while let Some((new, _)) = rx.receive(old).await {
            if GameBoard::get().calculate_winner() {
                GameStatus::mutate(StatusChange::Won);
            } else {
                NextPlayer::mutate(NextPlayerChange::Next);
            }
            old = new;
        }
    }
}
```

The turn-checker grabs a receiver for the GameBoard and waits for events. When an event arrives, it uses the model 
to check if we have a winner, and either ends the game, or flips the player, using the relevant mutators. The 
mutators for those stores push those changes down the channels so that the DOM is updated everywhere that is 
listening on related receivers.

```rust
fn square(id: SquareID) -> Node {
    button!(Square::formatted(id, |s| {
        format!("{}", s.mark)
    }))
    .class("square")
    .on_event("click", (), move |_, _| {
        use SquareMark::Empty;
        use Status::Playing;

        let status = GameStatus::get();
        let current = Square::get(id).mark;
        if status == Playing && current == Empty {
            Square::mutate(id, &SquareChange::Mark(NextPlayer::get()));
            GameBoard::notify();
        }
    })
    .into()
}
```

The ```square()``` function generates the buttons and sets up the event. It has a bit of logic around whether to 
accept the click, but if so, then it mutates the square to the current player's mark, and notifies the 
```GameBoard```. This triggers the turn-checker, which was looping, listening on the GameBoard's receiver.

Satisfy yourself now that if we put:

```rust
    GameBoard::node(),
    GameBoard::node(),
    GameBoard::node()
``` 

into ```game()```, we will see three boards that are playing the same game. All three would run turn-checkers 
(which would be weird) but they will render the same square state from the static GameBoard singleton and Square 
relation.

# Do you believe this is neater?

We have done a lot of work to really separate the model and the view, and the views from each other. This is not 
quite enough return for what we have invested yet, but we have laid critical groundwork for very powerful back-end
integration.

Next article, I'll explore some simple extensions to ```trait Relation``` that will let us fetch objects 
from a remote back-end, render them as *loading...* until they arrive, make local changes speculatively, and 
confirm them (or error) when the fetch returns to us with the server's outcome.