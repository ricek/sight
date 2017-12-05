package main

import (
	"fmt"
	"html"
	"net/http"

	vision "cloud.google.com/go/vision/apiv1"
	"google.golang.org/appengine"
	"google.golang.org/appengine/log"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "GET, %q\n", html.EscapeString(r.URL.Path))
	})

	http.HandleFunc("/emotion", GetEmotion)

	//log.Println("Listening...")
	http.ListenAndServe(":8080", nil)
	appengine.Main()
}

// GetEmotion returns the emotion of the given face
func GetEmotion(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" {
		fmt.Fprintf(w, "GET, %q\n", html.EscapeString(r.URL.Path))
		return
	}

	// Google Vision API
	// ctx := context.Background()
	ctx := appengine.NewContext(r)

	// Prepare form for upload
	file, header, err := r.FormFile("image")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	log.Infof(ctx, "File uploaded successfully: %s", header.Filename)

	// Creates a client
	client, err := vision.NewImageAnnotatorClient(ctx)
	if err != nil {
		log.Errorf(ctx, "Failed to create client: %v", err)
		//log.Fatalf("Failed to create client: %v", err)
	}

	image, err := vision.NewImageFromReader(file)
	if err != nil {
		log.Errorf(ctx, "Failed to create image: %v", err)
		//log.Fatalf("Failed to create image: %v", err)
	}

	// Get faces from the Vision API for an image at the given file path
	annotations, err := client.DetectFaces(ctx, image, nil, 10)
	if err != nil {
		log.Errorf(ctx, "Failed to detect faces: %v", err)
		//log.Fatal("Failed to detect faces")
	}

	if len(annotations) == 0 {
		log.Infof(ctx, "No faces found.")
		// fmt.Println("No faces found.")
	} else {
		joy := int(annotations[0].JoyLikelihood)
		anger := int(annotations[0].AngerLikelihood)
		sorrow := int(annotations[0].SorrowLikelihood)
		confidence := annotations[0].DetectionConfidence * 100

		log.Infof(ctx, "Faces: %v | Confidence: %v\nJoy: %v   Anger: %v   Sorrow: %v\n", len(annotations), confidence, joy, anger, sorrow)
		// fmt.Printf("Faces: %v | Confidence: %v\nJoy: %v   Anger: %v   Sorrow: %v\n", len(annotations), confidence, joy, anger, sorrow)

		threshold := (joy+anger+sorrow)/3.0 + 1
		if confidence > 65 && confidence < 80 {
			threshold = 2
		} else if confidence >= 80 {
			threshold = 1
		}

		switch {
		case joy >= threshold && joy >= anger && joy >= sorrow:
			w.Write([]byte("happy\n"))
		case anger >= threshold && anger >= joy && anger >= sorrow:
			w.Write([]byte("angry\n"))
		case sorrow >= threshold && sorrow >= joy && sorrow >= anger:
			w.Write([]byte("sad\n"))
		default:
			w.Write([]byte("okay\n"))
		}
	}
	return
}
