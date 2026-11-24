function printGuide(card) {
  const disclosures = [...card.querySelectorAll("details:not([open])")];
  const images = [...card.querySelectorAll('img[loading="lazy"]')];
  disclosures.forEach(details => { details.open = true; });
  images.forEach(image => { image.loading = "eager"; });
  window.addEventListener("afterprint", () => {
    disclosures.forEach(details => { details.open = false; });
    images.forEach(image => { image.loading = "lazy"; });
  }, { once: true });
  window.print();
}
