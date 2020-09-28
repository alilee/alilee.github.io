+++
title = "Next-gen Rust Web Apps"
date = 2020-09-28
description = "Towards a Svelte Fulcro in Rust"

[taxonomies]
tags = ["rust"]
+++

This is an homage to this absolute [work of art](http://www.sheshbabu.com/posts/rust-wasm-yew-single-page-application/) by Shesh Babu.

# What and why

Rust's strong typing and fearless concurrency means we can skip virtual DOM differencing. 

In the JavaScript world, avoiding the vDOM is the bread and butter of [Svelte](https://svelte.dev) 
started by Rich Harris, which uses compile-time code generation to assist.

When I can't have static typing I love Clojure, and have spent some time reviewing and 
playing with the stupendous full-stack Clojure SPA framework [Fulcro](http://book.fulcrologic.com) 
by Tony Kay (and associated back-end enabler [Pathom](https://blog.wsscode.com/pathom/) 
by Wilker Lucio). It does use vDOM, leveraging Clojure immutable/concurrent data structures 
for time travel superpowers.

For me, the major innovation (among many) in Fulcro is the use of a browser-side normalised database 
which is queried to populate properties for components. This means that updating (*mutating*) 
a uniquely-keyed item results in the update trivially propagating to any and all components 
referencing the data through that identifier. In Shesh Babu's language: all state is App state.
 
This article, or series of articles, is going to share my findings and thinking on the 
state of the nation in Rust front-end frameworks which are avoiding the vDOM strategy.

There are actually two Rust front-end frameworks with significant progress already, and they are 
awesome:
- [mogwai](https://crates.io/crates/mogwai) by Schell Scivally
- [valerie](https://crates.io/crates/valerie) by Emmanuel Antony

# Our lense: the React tutorial TicTacToe

The official React site offers a [guided introduction](https://reactjs.org/tutorial/tutorial.html) 
by progressively implementing a client-side tic-tac-toe game (also known as *noughts and crosses*). 
They don't explore a back-end, routing or forms, or many of the other SPA complexities. 

For us, it is just enough to highlight the potential of the two Rust frameworks above and paint 
a picture of how these advanced extensions can be easily incorporated, and gives us a solid 
reference point from the old world.

# Our approach

This is the first in a series of articles showing how the two frameworks might attack the example 
application, and then show some code which extends the frameworks to incorporate Fulcro-like app 
state.

My code will concentrate on the ergonomics of the frameworks from the perspective of the SPA-writer.