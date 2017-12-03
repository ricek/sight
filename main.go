package main

import (
	"github.com/joho/godotenv"
	"log"
	"os"

	"bytes"
	"io"
	"io/ioutil"
	"net/http"
	s "strings"
	"time"

	vision "cloud.google.com/go/vision/apiv1"
	"github.com/gorilla/mux"
	fb "github.com/huandu/facebook"
	"github.com/tidwall/gjson"
	"golang.org/x/net/context"
)

func main() {
	// Load dotenv library to read local system variables
	err := godotenv.Load()
	if err != nil {
		log.Fatal("Error loading .env file")
	}

	router := mux.NewRouter()

	router.HandleFunc("/upload", handleFacial).Methods("POST")
	router.HandleFunc("/ocr", handleEmotion).Methods("POST")

	log.Println("Server listening...")
	http.ListenAndServe(":8080", router)
}

func handleFacial(w http.ResponseWriter, r *http.Request) {
	log.Println("//==================================//")
	fn, header, _ := r.FormFile("image")
	defer fn.Close()

	f, _ := os.Create("./images/" + header.Filename)
	defer f.Close()

	log.Println("Received image:", header.Filename)
	io.Copy(f, fn)

	log.Println("Uploading image...")
	photo_id := uploadImage(header.Filename)

	log.Println("Recognizing image... \t ID:", photo_id)
	time.Sleep(time.Second * 3)
	person := recognizeImage(photo_id)

	log.Println("The person is " + person.Name + " with an ID of " + person.Fbid)

	log.Println("Now deleting...")
	is_deleted := deleteImage(photo_id)
	log.Println("Image deletion successful:", is_deleted)

	log.Println("Removing cached image")
	err := os.Remove("./images/" + header.Filename)
	if err != nil {
		log.Fatal("Error removing cached image")
	}
	log.Println("Succesfully removed cache.")

	w.Write([]byte(person.Name))
}

func handleEmotion(w http.ResponseWriter, r *http.Request) {

	log.Println("//==================================//")
	fn, header, _ := r.FormFile("image")
	defer fn.Close()

	f, _ := os.Create("./images/" + header.Filename)
	defer f.Close()

	log.Println("Received image:", header.Filename)
	io.Copy(f, fn)

	ctx := context.Background()

	// Creates a client.
	client, err := vision.NewImageAnnotatorClient(ctx)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	file, err := os.Open("./images/" + header.Filename)
	if err != nil {
		log.Fatalf("Failed to read file: %v", err)
	}
	defer file.Close()
	image, err := vision.NewImageFromReader(file)
	if err != nil {
		log.Fatalf("Failed to create image: %v", err)
	}

	labels, err := client.DetectTexts(ctx, image, nil, 10)
	if err != nil {
		log.Fatalf("Failed to detect labels: %v", err)
	}

	log.Println("Text:")

	log.Println(labels[0].Description)

	w.Write([]byte(labels[0].Description))
}

const FB_URL = "https://www.facebook.com/photos/tagging/recognition/?dpr=2"

type Person struct {
	Name        string
	Fbid        string
	Facebox_url string
}

func uploadImage(filename string) string {
	res, err := fb.Post("/me/photos", fb.Params{
		"source":       fb.File("./images/" + filename),
		"access_token": os.Getenv("FB_ACCESSTOKEN"),
	})

	if err != nil {
		log.Fatal("Error posting image", err)
	}

	var return_string = s.TrimSpace(res["id"].(string))

	return return_string
}

func deleteImage(photo_id string) bool {
	res, err := fb.Delete(photo_id, fb.Params{
		"access_token": os.Getenv("FB_ACCESSTOKEN"),
	})

	if err != nil {
		log.Fatal("Error deleting image", err)
	}

	return res["success"].(bool)
}

func recognizeImage(photo_id string) Person {

	var data = "recognition_project=composer_facerec&photos[0]=" + s.TrimSpace(photo_id) + "&target&is_page=false&include_unrecognized_faceboxes=true&include_face_crop_src=true&include_recognized_user_profile_picture=false&include_low_confidence_recognitions=true&__a=1&fb_dtsg=" + os.Getenv("FB_DTSG")

	form_data := []byte(data)

	req, _ := http.NewRequest("POST", FB_URL, bytes.NewBuffer(form_data))
	req.Header.Add("accept", "*/*")
	req.Header.Add("accept-encoding", "application/json")
	req.Header.Add("accept-language", "en-US,en;q=0.9")
	req.Header.Add("content-length", "711")
	req.Header.Add("content-type", "application/x-www-form-urlencoded")
	req.Header.Add("cookie", os.Getenv("FB_COOKIE"))
	req.Header.Add("dnt", "1")
	req.Header.Add("origin", "https://www.facebook.com")
	req.Header.Add("referrer", os.Getenv("FB_ACCOUNTURL"))
	req.Header.Add("user-agent", "Vizio / GoRecog 0.1")
	req.Header.Add("x_fb_background_state", "1")

	client := &http.Client{}

	var faceboxes string

	for i := 0; i < 10; i++ {
		res, err := client.Do(req)
		if err != nil {
			log.Fatal("Error querying Facebook tag API", err)
		}
		defer res.Body.Close()
		body, _ := ioutil.ReadAll(res.Body)

		recog_data := s.Replace(string(body), "for (;;);", "", -1)

		log.Println(recog_data)

		fboxes := gjson.Get(recog_data, "payload.0.faceboxes")

		if fboxes.Exists() {
			faceboxes = fboxes.String()
			break
		}

	}

	fbid := gjson.Get(faceboxes, "0.recognitions.0.user.fbid")
	name := gjson.Get(faceboxes, "0.recognitions.0.user.name")

	p := Person{
		Name: name.String(),
		Fbid: fbid.String(),
	}

	return p
}
