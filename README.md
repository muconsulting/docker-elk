#Ubuntu Dockerfile

A Dockerfile that produces a Docker Image for [ELK Stack](http://www.elasticsearch.com/).

## Usage

### Build the image

To create the image `muconsulting/elk`, execute the following command on the `docker-elk` folder:

```
$ docker build -t muconsulting/elk .
```

### Run the image

To run the image:

```
$ docker run -ti --rm --name elk  muconsulting/elk
```

## Copyright

Copyright (c) 2015 Sylvain Gibier. See [LICENSE](https://github.com/muconsulting/docker-elk/blob/master/LICENSE) for details.
