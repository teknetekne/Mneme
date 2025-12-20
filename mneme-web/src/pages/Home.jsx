import Navbar from '../components/Navbar'
import Hero from '../components/Hero'
import FeatureCarousel from '../components/FeatureCarousel'
import Footer from '../components/Footer'

export default function Home() {
    return (
        <>
            <Navbar />
            <main>
                <Hero />
                <FeatureCarousel />
            </main>
            <Footer />
        </>
    )
}
