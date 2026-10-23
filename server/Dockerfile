FROM node:24-alpine
WORKDIR /app
COPY --chown=node:node server.mjs package.json ./
USER node
ENV HOST=0.0.0.0 PORT=8080
EXPOSE 8080
CMD ["node", "server.mjs"]
