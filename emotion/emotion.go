package emotion

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	// Imports the Google Cloud Vision API client package
	vision "cloud.google.com/go/vision/apiv1"
	"golang.org/x/net/context"
)

func init() {
	// Refer to these functions so that goimports is happy before boilerplate is inserted.
	_ = context.Background()
	_ = vision.ImageAnnotatorClient{}
	_ = os.Open
}

// GetEmotion returns the emotion of the given face
func GetEmotion(url string) string {
	// Getting the requested image

	resp, err := http.Get(url)
	if err != nil {
		log.Fatalf("Failed to get image: %v", err)
	}
	defer resp.Body.Close()

	// Create new image for writing
	img, err := os.Create("emotion/image.jpg")
	if err != nil {
		log.Fatal(err)
	}

	// Copy the dump from http response body to the image file
	size, err := io.Copy(img, resp.Body)
	if err != nil {
		log.Fatal(err)
	}
	img.Close()

	// Log for image size
	fmt.Println("File size: ", size)

	/********************************/
	/********** Vision API **********/
	/********************************/
	ctx := context.Background()

	// Creates a client
	client, err := vision.NewImageAnnotatorClient(ctx)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	f, err := os.Open("emotion/image.jpg")
	if err != nil {
		log.Fatalf("Failed to read file: %v", err)
	}
	defer f.Close()

	image, err := vision.NewImageFromReader(f)
	if err != nil {
		log.Fatalf("Failed to create image: %v", err)
	}

	// Loading with gs:// or public URL
	// image := vision.NewImageFromURI(url)
	// fmt.Printf("%v\n", image)

	// Get faces from the Vision API for an image at the given file path
	annotations, err := client.DetectFaces(ctx, image, nil, 10)
	if err != nil {
		log.Fatal("Failed to detect faces")
	}

	if len(annotations) == 0 {
		fmt.Println("No faces found.")
	} else {
		joy := int(annotations[0].JoyLikelihood)
		anger := int(annotations[0].AngerLikelihood)
		sorrow := int(annotations[0].SorrowLikelihood)
		confidence := annotations[0].DetectionConfidence * 100

		fmt.Printf("Faces: %v | Confidence: %v\nJoy: %v   Anger: %v   Sorrow: %v\n", len(annotations), confidence, joy, anger, sorrow)

		threshold := (joy+anger+sorrow)/3.0 + 1
		if confidence > 65 && confidence < 80 {
			threshold = 2
		} else if confidence >= 80 {
			threshold = 1
		}

		switch {
		case joy >= threshold && joy >= anger && joy >= sorrow:
			return "happy"
		case anger >= threshold && anger >= joy && anger >= sorrow:
			return "angry"
		case sorrow >= threshold && sorrow >= joy && sorrow >= anger:
			return "sad"
		default:
			return "meh"
		}
	}
	return "meh"
}
