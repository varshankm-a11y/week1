FROM nginx:alpine
RUN apk update && apk upgrade --no-cache
RUN echo "<h1>EKS Production Application - Deployed via ECR</h1>" > /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
