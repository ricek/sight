# Insight (originally called Sight)
*Created by:
Najm Sheikh (hello@najmsheikh.me)
Liang Gao (lianggao@outlook.com)
Nathaniel Ostrer (nathaniel_ostrer@brown.edu)
Zak Wegweiser (zak_wegweiser@brown.edu)*

[![Sight Demonstration](https://i.vimeocdn.com/video/671311644_640.webp)](https://vimeo.com/246362146)

## Inspiration
Imagine a world where your best friend is standing in front of you, but you can't see them. Or you go to read a menu, but you are not able to because the restaurant does not have specialized brail menus. For millions of visually impaired people around the world, those are not hypotheticals, they are facts of life.

Hollywood has largely solved this problem in entertainment. Audio descriptions allow the blind or visually impaired to follow the plot of movies easily. With Sight, we are trying to bring the power of audio description to everyday life.

## What it does
Sight is an app that allows the visually impaired to recognize their friends, get an idea of their surroundings, and have written text read aloud. The app also uses voice recognition to listen for speech commands to identify objects, people or to read text.

## How we built it
The front-end is a native iOS app written in Swift and Objective-C with XCode. We use Apple's native vision and speech API's to give the user intuitive control over the app.

The back-end service is written in Go and is served with NGrok.

We repurposed the Facebook tagging algorithm to recognize a user's friends. When the Sight app sees a face, it is automatically uploaded to the back-end service. The back-end then "posts" the picture to the user's Facebook privately. If any faces show up in the photo, Facebook's tagging algorithm suggests possibilities for who out of the user's friend group they might be. We scrape this data from Facebook to match names with faces in the original picture. If and when Sight recognizes a person as one of the user's friends, that friend's name is read aloud.

We make use of the Google Vision API in three ways:

To run sentiment analysis on people's faces, to get an idea of whether they are happy, sad, surprised etc.
To run Optical Character Recognition on text in the real world which is then read aloud to the user.
For label detection, to indentify objects and surroundings in the real world which the user can then query about.

## Challenges we ran into
There were a plethora of challenges we experienced over the course of the hackathon.

Each member of the team wrote their portion of the back-end service a language they were comfortable in. However when we came together, we decided that combining services written in different languages would be overly complicated, so we decided to rewrite the entire back-end in Go.

When we rewrote portions of the back-end in Go, this gave us a massive performance boost. However, this turned out to be both a curse and a blessing. Because of the limitation of how quickly we are able to upload images to Facebook, we had to add a workaround to ensure that we do not check for tag suggestions before the photo has been uploaded.

When the Optical Character Recognition service was prototyped in Python on Google App Engine, it became mysteriously rate-limited by the Google Vision API. Re-generating API keys proved to no avail, and ultimately we overcame this by rewriting the service in Go.

## Accomplishments that we're proud of
Each member of the team came to this hackathon with a very disjoint set of skills and ideas, so we are really glad about how well we were able to build an elegant and put together app.

Facebook does not have an official algorithm for letting apps use their facial recognition service, so we are proud of the workaround we figured out that allowed us to use Facebook's powerful facial recognition software.

We are also proud of how fast the Go back-end runs, but more than anything, we are proud of building a really awesome app.

## What we learned
Najm taught himself Go over the course of the weekend, which he had no experience with before coming to YHack.

Nathaniel and Liang learned about the Google Vision API, and how to use it for OCR, facial detection, and facial emotion analysis.

Zak learned about building a native iOS app that communicates with a data-rich APIs.

We also learned about making clever use of Facebook's API to make use of their powerful facial recognition service.

Over the course of the weekend, we encountered more problems and bugs than we'd probably like to admit. Most of all we learned a ton of valuable problem-solving skills while we worked together to overcome these challenges.

## What's next for Sight
If Facebook ever decides to add an API that allows facial recognition, we think that would allow for even more powerful friend recognition functionality in our app.

Ultimately, we plan to host the back-end on Google App Engine.
