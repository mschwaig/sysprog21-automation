package main

import (
	"net/http"
	"os/exec"
	"os"
	"io/ioutil"
	"io"
	"flag"
	"fmt"
	"log"
	// TODO: In-Memory Temp files in GO. See:
        // https://terinstock.com/post/2018/10/memfd_create-Temporary-in-memory-files-with-Go-and-Linux/
	//"golang.org/x/sys/unix"
)

var eval_script_path string

type flushWriter struct {
	f http.Flusher
	w io.Writer
}

func (fw *flushWriter) Write(p []byte) (n int, err error) {
	n, err = fw.w.Write(p)
	if fw.f != nil {
		fw.f.Flush()
	}
	return
}

func main() {
    flag.StringVar(&eval_script_path, "e", "", "eval script path")
    flag.Parse()
    if (eval_script_path == "") {
	log.Print("Error. You must provied an eval script path using the -e command line flag.");
	os.Exit(1);
    }
    http.HandleFunc("/upload", FileUpload)
    log.Fatal(http.ListenAndServe(":8080", nil))
}


func FileUpload(w http.ResponseWriter, r *http.Request) {
	r.ParseMultipartForm(16 << 20) // 16 MB maximum form size
	w.Header().Set("Access-Control-Allow-Origin", "*")
	file, file_header, err := r.FormFile("factory")
	if err != nil {
		w.WriteHeader(501)
		// TODO: do I have to do more for error handling here?
	}
	defer file.Close()

	// flush writes right away for smooth output
	// See: https://stackoverflow.com/q/19292113
	fw := flushWriter{w: w}
	if f, ok := w.(http.Flusher); ok {
		fw.f = f
	}

	// create tmp file with file handle/path we can pass to nix
	tmpfile, err := ioutil.TempFile("", "*_"+file_header.Filename)
	if err != nil {
		log.Fatal(err)
	}

	if _, err := io.Copy(tmpfile, file); err != nil {
		log.Fatal(err)
	}
	//if err := tmpfile.Close(); err != nil {
	//	log.Fatal(err)
	//}
	// TODO: fix this mess / take a look at error handling

	cmd := exec.Command(eval_script_path, tmpfile.Name())
        cmd.Stdout = &fw
        cmd.Stderr = &fw
        err = cmd.Run()
        if err != nil {
          log.Print(err)
        }

	defer os.Remove(tmpfile.Name())
	fmt.Fprintf(&fw, "done\n")
}
