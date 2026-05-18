/// Screenshot carousel for the detail panel: one slide at a time,
/// a prev/next button on each side, and a dot per slide underneath.
/// Pure CSS transform track (no scroll), so it works regardless of
/// trackpad/overflow quirks. Wraps at the ends so the arrows never
/// dead-end; ←/→ also drive it when the carousel has focus.
///
/// Clicking a slide (or the expand button) opens a full-screen
/// lightbox — the same carousel, blown up over a dimmed backdrop,
/// portalled to <body> so it escapes the detail panel's stacking
/// context. The slide index is SHARED between inline + lightbox, so
/// you open where you were and close where you ended up.

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Button } from "@base/primitives/button";
import "@base/primitives/button/button.css";
import { Icon } from "@base/primitives/icon";
import "@base/primitives/icon/icon.css";
import { chevronLeft } from "@base/primitives/icon/icons/chevron-left";
import { chevronRight } from "@base/primitives/icon/icons/chevron-right";
import { expand } from "@base/primitives/icon/icons/expand";
import { x as xIcon } from "@base/primitives/icon/icons/x";

interface Props {
  images: string[];
  appName: string;
}

export function ScreenshotCarousel({ images, appName }: Props) {
  const [index, setIndex] = useState(0);
  const [lightbox, setLightbox] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const count = images.length;

  // Clamp if the image set changes under us (switching apps reuses
  // this component via React reconciliation).
  useEffect(() => {
    setIndex((i) => (i >= count ? 0 : i));
  }, [count]);

  // Lightbox key handling, capture-phase + stopPropagation so it
  // closes the OVERLAY only — AppDetail's bubble-phase window
  // Escape listener (which closes the whole panel) must not also
  // fire while the lightbox is up. ←/→ navigate.
  useEffect(() => {
    if (!lightbox) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        e.preventDefault();
        setLightbox(false);
      } else if (e.key === "ArrowLeft") {
        e.stopPropagation();
        setIndex((i) => ((i - 1 + count) % count) || 0);
      } else if (e.key === "ArrowRight") {
        e.stopPropagation();
        setIndex((i) => (i + 1) % count);
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [lightbox, count]);

  if (count === 0) return null;

  const go = (next: number) => setIndex(((next % count) + count) % count);

  // Shared slide track + nav + dots, used inline and (bigger) in
  // the lightbox. `variant` only swaps class names for sizing.
  const Track = ({ variant }: { variant: "inline" | "lightbox" }) => (
    <>
      <div className={`ms-carousel__stage ms-carousel__stage--${variant}`}>
        <div
          className="ms-carousel__track"
          style={{ transform: `translateX(-${index * 100}%)` }}
        >
          {images.map((src, i) => (
            <div className="ms-carousel__slide" key={src}>
              <img
                src={src}
                alt={`${appName} screenshot ${i + 1} of ${count}`}
                draggable={false}
                loading="lazy"
                onClick={
                  variant === "inline"
                    ? () => setLightbox(true)
                    : undefined
                }
                style={
                  variant === "inline"
                    ? { cursor: "zoom-in" }
                    : undefined
                }
              />
            </div>
          ))}
        </div>

        {variant === "inline" && (
          <div className="ms-carousel__expand">
            <Button
              variant="secondary"
              size="sm"
              iconOnly
              icon={expand}
              aria-label="View screenshots full screen"
              onClick={() => setLightbox(true)}
            />
          </div>
        )}

        {count > 1 && (
          <>
            <div className="ms-carousel__nav ms-carousel__nav--prev">
              <Button
                variant="secondary"
                size="sm"
                iconOnly
                icon={chevronLeft}
                aria-label="Previous screenshot"
                onClick={() => go(index - 1)}
              />
            </div>
            <div className="ms-carousel__nav ms-carousel__nav--next">
              <Button
                variant="secondary"
                size="sm"
                iconOnly
                icon={chevronRight}
                aria-label="Next screenshot"
                onClick={() => go(index + 1)}
              />
            </div>
          </>
        )}
      </div>

      {count > 1 && (
        <div className="ms-carousel__dots" role="tablist">
          {images.map((src, i) => (
            <button
              key={src}
              type="button"
              role="tab"
              aria-selected={i === index}
              aria-label={`Go to screenshot ${i + 1}`}
              className={
                "ms-carousel__dot" +
                (i === index ? " ms-carousel__dot--active" : "")
              }
              onClick={() => setIndex(i)}
            />
          ))}
        </div>
      )}
    </>
  );

  return (
    <>
      <div
        className="ms-carousel"
        ref={rootRef}
        tabIndex={0}
        role="group"
        aria-roledescription="carousel"
        aria-label={`${appName} screenshots`}
        onKeyDown={(e) => {
          if (e.key === "ArrowLeft") {
            e.preventDefault();
            go(index - 1);
          } else if (e.key === "ArrowRight") {
            e.preventDefault();
            go(index + 1);
          }
        }}
      >
        <Track variant="inline" />
      </div>

      {lightbox &&
        createPortal(
          <div
            className="ms-lightbox"
            role="dialog"
            aria-modal="true"
            aria-label={`${appName} screenshots, full screen`}
            onClick={() => setLightbox(false)}
          >
            <button
              type="button"
              className="ms-lightbox__close"
              aria-label="Close full screen"
              onClick={() => setLightbox(false)}
            >
              <Icon icon={xIcon} size="base" color="currentColor" />
            </button>
            <div
              className="ms-lightbox__inner"
              onClick={(e) => e.stopPropagation()}
            >
              <Track variant="lightbox" />
            </div>
          </div>,
          document.body,
        )}
    </>
  );
}
