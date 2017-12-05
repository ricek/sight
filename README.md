# Vision API

Google Cloud Vision API detects individual objects and faces within images, and finds and reads printed words contained within images. Along with Google App Engine, the app analyzes image uploaded in the http form request and returns sentiment analysis on people's facial expression.

## Deploying the Application
1. Download the [Google Cloud SDK](https://cloud.google.com/sdk/docs/)
2. Open the [Google Developers Console](https://console.developers.google.com/) and click Create Project.
3. Clone this repo and change the Cloud configuration `gcloud config set project <project-id>`
4. Run the command `gcloud app deploy`
5. Enable [Vision API](https://console.developers.google.com/apis/dashboard) for the project 

Test `curl https://<project-id>.appspot.com/emotion -F "image=@face.jpg"`

## Notes
1. `appengine.Main()` if top level package main with function main
2. `ctx := appengine.NewContext(r)` for a valid request context on App Engine
3. `import "google.golang.org/appengine/log"` to handle request logs and application logs on App Engine
